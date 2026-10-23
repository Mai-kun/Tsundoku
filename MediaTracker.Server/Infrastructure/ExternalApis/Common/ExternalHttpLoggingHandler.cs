using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// One line before and one after every external HTTP call, regardless of which of the dozen
/// sources fired it: HttpClientFactory's own System.Net.Http logs are drowned by the
/// "System -> Warning" Serilog override, so without this handler AniList/MangaDex/TMDB traffic
/// is invisible. Secrets in the query string are masked; GraphQL bodies are summarised
/// (operation name + variables), never dumped whole.
/// </summary>
public sealed partial class ExternalHttpLoggingHandler(
    ILogger<ExternalHttpLoggingHandler> logger) : DelegatingHandler
{
    private const int MaxSnippetLength = 120;
    private const int MaxVariableValueLength = 40;

    private static readonly HashSet<string> SecretParameters = new(StringComparer.OrdinalIgnoreCase)
    {
        "api_key", "apikey", "key", "client_id", "client_secret", "token",
    };

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var safeUrl = BuildSafeUrl(request.RequestUri);
        var graphqlContext = await DescribeGraphQlBodyAsync(request, cancellationToken);
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var response = await base.SendAsync(request, cancellationToken);
            stopwatch.Stop();
            var status = (int)response.StatusCode;
            string reason = response.ReasonPhrase ?? string.Empty;
            var message = "[ExternalHttp] <-- {StatusCode} ({ReasonPhrase}) from {Method} {Url}{GraphQl} in {ElapsedMs}ms";
            if (response.IsSuccessStatusCode)
            {
                logger.LogInformation(message, status, reason, request.Method, safeUrl, graphqlContext, stopwatch.ElapsedMilliseconds);
            }
            else
            {
                logger.LogWarning(message, status, reason, request.Method, safeUrl, graphqlContext, stopwatch.ElapsedMilliseconds);
            }

            return response;
        }
        catch (Exception error)
        {
            stopwatch.Stop();
            logger.LogWarning(
                error,
                "[ExternalHttp] .. {Method} {Url}{GraphQl} failed after {ElapsedMs}ms: {Message}",
                request.Method,
                safeUrl,
                graphqlContext,
                stopwatch.ElapsedMilliseconds,
                error.Message);
            throw;
        }
    }

    /// <summary>Query string with credentials flattened to *** (TMDB/Kinopoisk/Steam/IGDB style keys).</summary>
    private static string BuildSafeUrl(Uri? uri)
    {
        if (uri is null)
        {
            return "(no URL)";
        }

        if (string.IsNullOrWhiteSpace(uri.Query))
        {
            return uri.ToString();
        }

        var query = string.Join("&", uri.Query.TrimStart('?').Split('&').Select(part =>
        {
            var key = part.Split('=', 2)[0];
            var decoded = Uri.UnescapeDataString(key);
            return SecretParameters.Contains(decoded.Trim())
                ? $"{key}=***"
                : part;
        }));

        return $"{uri.GetLeftPart(UriPartial.Path)}?{query}";
    }

    /// <summary>
    /// Swaps the GraphQL body into a buffered copy (the original may be a single-shot stream)
    /// and returns the log suffix summarising it: operation name and the interesting variables.
    /// Empty string for anything that is not a JSON POST to a GraphQL endpoint.
    /// </summary>
    private static async Task<string> DescribeGraphQlBodyAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (request.Method != HttpMethod.Post
            || request.Content is null
            || request.RequestUri is null
            || !request.RequestUri.Host.Contains("graphql", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(
                request.Content.Headers.ContentType?.MediaType,
                "application/json",
                StringComparison.OrdinalIgnoreCase))
        {
            return string.Empty;
        }

        var bytes = await request.Content.ReadAsByteArrayAsync(cancellationToken);
        var buffered = new ByteArrayContent(bytes);
        foreach (var header in request.Content.Headers)
        {
            buffered.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }
        request.Content = buffered;

        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return string.Empty;
            }

            var operation =
                root.TryGetProperty("operationName", out var operationElement)
                && operationElement.ValueKind == JsonValueKind.String
                    ? operationElement.GetString()
                    : null;
            var query = root.TryGetProperty("query", out var queryElement)
                && queryElement.ValueKind == JsonValueKind.String
                    ? queryElement.GetString()
                    : null;
            operation ??= ExtractOperationName(query);

            var parts = new List<string>(3);
            if (!string.IsNullOrWhiteSpace(operation))
            {
                parts.Add(operation);
            }

            if (root.TryGetProperty("variables", out var variablesElement)
                && variablesElement.ValueKind == JsonValueKind.Object)
            {
                var summary = string.Join(
                    ", ",
                    variablesElement.EnumerateObject().Take(5).Select(property =>
                    {
                        var value = ClipValue(property.Value);
                        return value is null
                            ? property.Name
                            : $"{property.Name}={value}";
                    }));
                if (summary.Length > 0)
                {
                    parts.Add($"vars: {summary}");
                }
            }

            var snippet = Clip(query, MaxSnippetLength);
            if (snippet.Length > 0)
            {
                parts.Add($"'{snippet}'");
            }

            return parts.Count == 0 ? string.Empty : $" [{string.Join(" | ", parts)}]";
        }
        catch (JsonException)
        {
            return string.Empty; // malformed body: the server itself reports the parse failure
        }
    }

    /// <summary>Named operations: "query Search(...) {...}" -> Search; anonymous ones stay nameless.</summary>
    private static string? ExtractOperationName(string? query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return null;
        }

        var match = OperationNameRegex().Match(query);
        return match.Success ? match.Groups[1].Value : null;
    }

    private static string Clip(string? value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length <= maxLength)
        {
            return value ?? string.Empty;
        }
        return value[..maxLength] + "…";
    }

    private static string? ClipValue(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.String => Clip(element.GetString(), MaxVariableValueLength),
            JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => element.GetRawText(),
            _ => null,
        };
    }

    [GeneratedRegex("query\\s+(\\w+)", RegexOptions.Compiled)]
    private static partial Regex OperationNameRegex();
}
