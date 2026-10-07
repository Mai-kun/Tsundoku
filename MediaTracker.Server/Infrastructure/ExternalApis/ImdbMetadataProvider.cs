using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Utilities;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class ImdbMetadataProvider(
    IHttpClientFactory httpClientFactory,
    ILogger<ImdbMetadataProvider>? logger = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "imdb",
        Name: "IMDb",
        Description: "Internet Movie Database movies and TV shows metadata provider",
        MediaTypes: ["movie", "tvshow"],
        BaseAddress: "https://v2.sg.media-imdb.com/suggestion/",
        Priority: 2);

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var clean = query.Trim();
        if (clean.Length == 0) return [];

        var firstChar = PartitionOf(clean);
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"{firstChar}/{Uri.EscapeDataString(clean.ToLowerInvariant())}.json";
        var url = client.BaseAddress + endpoint;

        try
        {
            ExternalApiLog.Querying(logger, Name, "movie/tvshow", clean);
            var sw = Stopwatch.StartNew();
            var res = await client.GetFromJsonAsync<ImdbSuggestionResponse>(endpoint, ct);
            if (res?.D is null || res.D.Count == 0)
            {
                ExternalApiLog.Returned(logger, Name, 0, sw.ElapsedMilliseconds);
                return [];
            }

            var mapped = res.D
                .Where(item => !string.IsNullOrWhiteSpace(item.Id) && !string.IsNullOrWhiteSpace(item.L))
                .Select(MapItem)
                .ToList();

            ExternalApiLog.Returned(logger, Name, mapped.Count, sw.ElapsedMilliseconds);
            return mapped;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            // The suggestion CDN has no partition for a query it cannot match, and answers 404 rather
            // than an empty list. Uncaught it reached the aggregator as SourceUnavailableException, so
            // one unmatched prefix turned into a 502 "External metadata source is unavailable".
            ExternalApiLog.Failed(logger, Name, HttpStatusCode.NotFound, url);
            return [];
        }
    }

    /// <summary>
    /// The CDN only keeps <c>a-z</c> and <c>0-9</c> directories. <c>char.IsLetterOrDigit</c> also
    /// accepts Cyrillic, which built <c>suggestion/д/дюна.json</c> and 404'd on every Russian title.
    /// </summary>
    internal static string PartitionOf(string query)
    {
        var first = char.ToLowerInvariant(query[0]);
        return first is >= 'a' and <= 'z' or >= '0' and <= '9'
            ? first.ToString(CultureInfo.InvariantCulture)
            : "a";
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var hasTitle = !string.IsNullOrWhiteSpace(title);
        ExternalMediaDto? result;
        if (hasTitle)
        {
            var results = await SearchAsync(title, ct);
            result = results.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
                     ?? (results.Count > 0 ? results[0] : null);
        }
        else
        {
            result = IsImdbId(externalId)
                ? new ExternalMediaDto
                {
                    ExternalId = externalId,
                    ExternalSource = "IMDb",
                    Title = externalId,
                    Type = "movie",
                    Ratings = []
                }
                : null;
        }

        if (result is null || !IsImdbId(externalId))
        {
            return result;
        }

        var meta = await FetchCinemetaAsync(externalId, hasTitle ? result.Type : null, ct);
        if (meta is null)
        {
            return result;
        }

        var rating = NumberOrNull(meta.ImdbRating);
        int? votes = NumberOrNull(meta.Votes) is { } rawVotes ? (int)rawVotes : null;
        var runtime = ParseRuntime(meta.Runtime);
        IReadOnlyList<ExternalRatingDto>? ratings = rating is not null
            ? [new ExternalRatingDto { Source = "IMDb", Rating = rating.Value, Votes = votes }]
            : result.Ratings;

        return result with
        {
            Title = hasTitle ? result.Title : meta.Name ?? result.Title,
            Type = hasTitle ? result.Type : meta.Type == "series" ? "tvshow" : "movie",
            Description = meta.Description ?? result.Description,
            RuntimeMinutes = runtime ?? result.RuntimeMinutes,
            Rating = rating ?? result.Rating,
            RatingVotes = votes ?? result.RatingVotes,
            Ratings = ratings,
            Genres = meta.Genres is { Count: > 0 } genres ? genres : result.Genres
        };
    }

    private const string CinemetaMetaUrl = "https://v3-cinemeta.strem.io/meta";

    private async Task<CinemetaMeta?> FetchCinemetaAsync(string externalId, string? type, CancellationToken ct)
    {
        var typedUrl = type is null
            ? null
            : $"{CinemetaMetaUrl}/{(type == "tvshow" ? "series" : "movie")}/{externalId}.json";

        try
        {
            var client = httpClientFactory.CreateClient(Id);
            if (typedUrl is not null)
            {
                var typed = await client.GetFromJsonAsync<CinemetaResponse>(typedUrl, ct);
                return typed?.Meta;
            }

            var series = await client.GetFromJsonAsync<CinemetaResponse>($"{CinemetaMetaUrl}/series/{externalId}.json", ct);
            if (series?.Meta is not null)
            {
                return series.Meta;
            }

            var movie = await client.GetFromJsonAsync<CinemetaResponse>($"{CinemetaMetaUrl}/movie/{externalId}.json", ct);
            return movie?.Meta;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, typedUrl ?? externalId);
            return null;
        }
    }

    private static double? NumberOrNull(JsonElement? element) => element?.ValueKind switch
    {
        JsonValueKind.String => double.TryParse(element.Value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? value
            : null,
        JsonValueKind.Number => element.Value.GetDouble(),
        _ => null
    };

    internal static int? ParseRuntime(string? runtime)
    {
        return runtime is null ? null : SpanParserExtensions.ParseDurationMinutes(runtime.AsSpan());
    }

    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            // A guaranteed hit. The default interface method searched for "test", which the CDN does
            // not carry, so every IMDb connection test reported a failure that was never a failure.
            var client = httpClientFactory.CreateClient(Id);
            using var resp = await client.GetAsync("h/hello.json", HttpCompletionOption.ResponseHeadersRead, ct);
            sw.Stop();

            if (resp.IsSuccessStatusCode)
            {
                ExternalApiLog.Returned(logger, Name, 1, sw.ElapsedMilliseconds);
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            ExternalApiLog.Failed(logger, Name, resp.StatusCode, client.BaseAddress + "h/hello.json");
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                $"IMDb CDN ответил {(int)resp.StatusCode} {resp.ReasonPhrase}");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                "Таймаут соединения с IMDb CDN (сервис не отвечает)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            ExternalApiLog.Failed(logger, Name, ex, "h/hello.json");
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"Ошибка сети: {ex.Message}");
        }
    }

    private static bool IsImdbId(string externalId) =>
        externalId.StartsWith("tt", StringComparison.OrdinalIgnoreCase);

    private static ExternalMediaDto MapItem(ImdbSuggestionItem item)
    {
        var isTv = item.Q is not null && (item.Q.Contains("tv", StringComparison.OrdinalIgnoreCase) || item.Q.Contains("series", StringComparison.OrdinalIgnoreCase));
        var type = isTv ? "tvshow" : "movie";

        return new ExternalMediaDto
        {
            ExternalId = item.Id,
            ExternalSource = "IMDb",
            Title = item.L ?? "Unknown",
            CoverUrl = item.I?.ImageUrl,
            ReleaseYear = item.Y,
            Type = type,
            Ratings = []
        };
    }

    private sealed class ImdbSuggestionResponse
    {
        [JsonPropertyName("d")]
        public List<ImdbSuggestionItem>? D { get; set; }
    }

    private sealed class ImdbSuggestionItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("l")]
        public string? L { get; set; }

        [JsonPropertyName("y")]
        public int? Y { get; set; }

        [JsonPropertyName("q")]
        public string? Q { get; set; }

        [JsonPropertyName("i")]
        public ImdbImage? I { get; set; }
    }

    private sealed class ImdbImage
    {
        [JsonPropertyName("imageUrl")]
        public string? ImageUrl { get; set; }
    }

    private sealed class CinemetaResponse
    {
        [JsonPropertyName("meta")]
        public CinemetaMeta? Meta { get; set; }
    }

    private sealed class CinemetaMeta
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("type")]
        public string? Type { get; set; }

        [JsonPropertyName("imdbRating")]
        public JsonElement? ImdbRating { get; set; }

        [JsonPropertyName("runtime")]
        public string? Runtime { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        [JsonPropertyName("genres")]
        public List<string>? Genres { get; set; }

        [JsonPropertyName("votes")]
        public JsonElement? Votes { get; set; }
    }
}
