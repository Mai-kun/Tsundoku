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
    ILogger<ExternalHttpLoggingHandler> logger,
    RateLimitTracker? rateLimitTracker = null) : DelegatingHandler
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
            TrackRateLimits(request, response);
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

    private void TrackRateLimits(HttpRequestMessage request, HttpResponseMessage response)
    {
        if (rateLimitTracker is null) return;

        var is429 = (int)response.StatusCode == 429;

        var remainingHeader = GetHeader(response, "X-RateLimit-Remaining")
            ?? GetHeader(response, "RateLimit-Remaining")
            ?? GetHeader(response, "X-Rate-Limit-Remaining");

        var limitHeader = GetHeader(response, "X-RateLimit-Limit")
            ?? GetHeader(response, "RateLimit-Limit")
            ?? GetHeader(response, "X-Rate-Limit-Limit");

        var resetHeader = GetHeader(response, "X-RateLimit-Reset")
            ?? GetHeader(response, "RateLimit-Reset")
            ?? GetHeader(response, "X-Rate-Limit-Reset")
            ?? GetHeader(response, "Retry-After");

        if (!is429 && remainingHeader is null && limitHeader is null && resetHeader is null)
        {
            return;
        }

        if (!int.TryParse(remainingHeader, out var remaining))
        {
            remaining = 0;
        }

        if (!int.TryParse(limitHeader, out var limit))
        {
            limit = 0;
        }

        var resetSeconds = ParseResetHeader(resetHeader);
        if (is429)
        {
            remaining = 0;
            if (resetSeconds <= 0) resetSeconds = 60;
        }

        var (providerKey, providerName) = ResolveProvider(request.RequestUri);
        rateLimitTracker.Update(providerKey, providerName, remaining, limit, resetSeconds);
    }

    private static string? GetHeader(HttpResponseMessage response, string headerName)
    {
        if (response.Headers.TryGetValues(headerName, out var values))
        {
            return values.FirstOrDefault();
        }

        if (response.Content != null && response.Content.Headers.TryGetValues(headerName, out var contentValues))
        {
            return contentValues.FirstOrDefault();
        }

        return null;
    }

    private static int ParseResetHeader(string? resetHeader)
    {
        if (string.IsNullOrWhiteSpace(resetHeader))
        {
            return 0;
        }

        if (double.TryParse(resetHeader, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var num))
        {
            if (num > 1_000_000_000)
            {
                var resetTime = DateTimeOffset.FromUnixTimeSeconds((long)num);
                var seconds = (int)Math.Ceiling((resetTime - DateTimeOffset.UtcNow).TotalSeconds);
                return Math.Max(0, seconds);
            }

            return Math.Max(0, (int)Math.Ceiling(num));
        }

        if (DateTimeOffset.TryParse(resetHeader, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var date))
        {
            var seconds = (int)Math.Ceiling((date - DateTimeOffset.UtcNow).TotalSeconds);
            return Math.Max(0, seconds);
        }

        return 0;
    }

    private static (string Key, string Name) ResolveProvider(Uri? uri)
    {
        if (uri is null) return ("unknown", "Unknown");

        var host = uri.Host;

        foreach (var descriptor in MetadataSourceRegistry.All)
        {
            if (Uri.TryCreate(descriptor.BaseAddress, UriKind.Absolute, out var baseUri))
            {
                if (string.Equals(baseUri.Host, host, StringComparison.OrdinalIgnoreCase) ||
                    host.EndsWith("." + baseUri.Host, StringComparison.OrdinalIgnoreCase))
                {
                    return (descriptor.Id.ToLowerInvariant(), descriptor.RatingSourceName);
                }
            }
        }

        if (host.Contains("anilist", StringComparison.OrdinalIgnoreCase)) return ("anilist", "AniList");
        if (host.Contains("mangadex", StringComparison.OrdinalIgnoreCase)) return ("mangadex", "MangaDex");
        if (host.Contains("themoviedb", StringComparison.OrdinalIgnoreCase) || host.Contains("tmdb", StringComparison.OrdinalIgnoreCase)) return ("tmdb", "TMDB");
        if (host.Contains("shikimori", StringComparison.OrdinalIgnoreCase)) return ("shikimori", "Shikimori");
        if (host.Contains("rawg", StringComparison.OrdinalIgnoreCase)) return ("rawg", "RAWG");
        if (host.Contains("steam", StringComparison.OrdinalIgnoreCase)) return ("steam", "Steam");
        if (host.Contains("kinopoisk", StringComparison.OrdinalIgnoreCase)) return ("kinopoisk", "Kinopoisk");
        if (host.Contains("simkl", StringComparison.OrdinalIgnoreCase)) return ("simkl", "Simkl");
        if (host.Contains("kitsu", StringComparison.OrdinalIgnoreCase)) return ("kitsu", "Kitsu");
        if (host.Contains("openlibrary", StringComparison.OrdinalIgnoreCase)) return ("openlibrary", "OpenLibrary");

        return (host.ToLowerInvariant(), host);
    }

    [GeneratedRegex("query\\s+(\\w+)", RegexOptions.Compiled)]
    private static partial Regex OperationNameRegex();
}
