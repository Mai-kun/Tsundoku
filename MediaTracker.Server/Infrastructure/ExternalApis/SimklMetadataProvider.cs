using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class SimklMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null,
    ILogger<SimklMetadataProvider>? logger = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "simkl",
        Name: "Simkl",
        Description: "Anime, TV shows and movies metadata & ratings tracking service",
        MediaTypes: ["anime", "movie", "tvshow"],
        BaseAddress: "https://api.simkl.com/",
        RequiresApiKey: true,
        Priority: 4,
        UserAgent: "MediaTracker/1.0");

    private readonly string _mediaType = serviceKey?.StartsWith("anime", StringComparison.OrdinalIgnoreCase) is true ? "anime"
        : serviceKey?.StartsWith("movie", StringComparison.OrdinalIgnoreCase) is true ? "movie"
        : serviceKey?.StartsWith("tvshow", StringComparison.OrdinalIgnoreCase) is true ? "tvshow"
        : "anime";

    private string ClientId => options.Value.GetKey(Id) ?? string.Empty;

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var clientId = ClientId;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            logger?.LogWarning("Simkl client id is not configured, search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);
        var endpoint =
            $"search/{SearchSegmentOf(_mediaType)}?q={Uri.EscapeDataString(query)}&extended=full"
            + $"&client_id={Uri.EscapeDataString(clientId)}&app-name=mediatracker&app-version=1.0";

        try
        {
            ExternalApiLog.Querying(logger, Name, _mediaType, query);
            var sw = Stopwatch.StartNew();
            using var resp = await client.GetAsync(endpoint, ct);
            if (!resp.IsSuccessStatusCode)
            {
                ExternalApiLog.Failed(logger, Name, resp.StatusCode, client.BaseAddress + endpoint);
                return [];
            }

            var items = await resp.Content.ReadFromJsonAsync<List<SimklItem>>(cancellationToken: ct);
            if (items is null || items.Count == 0)
            {
                ExternalApiLog.Returned(logger, Name, 0, sw.ElapsedMilliseconds);
                return [];
            }

            var mapped = items.ConvertAll(item => MapItem(item, _mediaType));
            ExternalApiLog.Returned(logger, Name, mapped.Count, sw.ElapsedMilliseconds);
            return mapped;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (HttpRequestException ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, client.BaseAddress + endpoint);
            return [];
        }
    }

    /// <summary>
    /// The search path is singular for every type. Only <c>endpoint_type</c> inside the response
    /// says "movies"; calling <c>/search/movies</c> 404s, which is why movie search was always empty.
    /// </summary>
    internal static string SearchSegmentOf(string mediaType) => mediaType switch
    {
        "movie" => "movie",
        "tvshow" => "tv",
        _ => "anime"
    };

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(title))
        {
            var results = await SearchAsync(title, ct);
            return results.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
                   ?? (results.Count > 0 ? results[0] : null);
        }

        // Search resolves ids like "Dune", not numeric catalog keys. A bare id needs the one-shot
        // catalog lookup instead, which the aggregator hits on refresh where no title is known yet.
        if (long.TryParse(externalId, out var simklId) && simklId > 0)
        {
            var detail = await FetchByIdAsync(simklId, ct);
            if (detail is not null) return detail;
        }

        var fallback = await SearchAsync(externalId, ct);
        return fallback.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
               ?? (fallback.Count > 0 ? fallback[0] : null);
    }

    private async Task<ExternalMediaDto?> FetchByIdAsync(long simklId, CancellationToken ct)
    {
        var clientId = ClientId;
        if (string.IsNullOrWhiteSpace(clientId)) return null;

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"{SearchSegmentOf(_mediaType)}/{simklId}?extended=full"
                       + $"&client_id={Uri.EscapeDataString(clientId)}&app-name=mediatracker&app-version=1.0";

        try
        {
            using var resp = await client.GetAsync(endpoint, ct);
            if (!resp.IsSuccessStatusCode) return null;

            var item = await resp.Content.ReadFromJsonAsync<SimklItem>(cancellationToken: ct);
            return item is null ? null : MapItem(item, _mediaType);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (HttpRequestException ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, client.BaseAddress + endpoint);
            return null;
        }
    }

    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var clientId = ClientId;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return new ConnectionTestResult(false, 0, "Client ID не указан");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            // A real keyed call. /search/id resolves one catalog entry and is the cheapest endpoint
            // that still runs the client_id check, so a wrong key fails here instead of the test
            // reporting a connection that only exists in the URL.
            var client = httpClientFactory.CreateClient(Id);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            var endpoint = "search/id?simkl=1&client_id=" + Uri.EscapeDataString(clientId)
                           + "&app-name=mediatracker&app-version=1.0";

            ExternalApiLog.Querying(logger, Name, _mediaType, "id:1 (connection test)");
            using var resp = await client.GetAsync(endpoint, HttpCompletionOption.ResponseHeadersRead, cts.Token);
            sw.Stop();

            if (resp.IsSuccessStatusCode)
            {
                ExternalApiLog.Returned(logger, Name, 1, sw.ElapsedMilliseconds);
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            ExternalApiLog.Failed(logger, Name, resp.StatusCode, client.BaseAddress + endpoint);

            var isCloudflare = resp.Headers.TryGetValues("Server", out var servers) &&
                               servers.Any(s => s.Contains("cloudflare", StringComparison.OrdinalIgnoreCase));

            if (isCloudflare && resp.StatusCode == HttpStatusCode.Forbidden)
            {
                return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                    "Доступ к Simkl заблокирован Cloudflare (ограничение региона/IP, требуется VPN или прокси)");
            }

            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                resp.StatusCode switch
                {
                    // 412 is Simkl's own answer for an unusable client_id, not an auth challenge.
                    (HttpStatusCode)412 => "Неверный Client ID (412 client_id failed)",
                    HttpStatusCode.Unauthorized => "Неверный Client ID (401 Unauthorized)",
                    HttpStatusCode.Forbidden => "Доступ запрещен сервисом Simkl (403 Forbidden)",
                    HttpStatusCode.NotFound => "Эндпоинт не найден (404 Not Found)",
                    HttpStatusCode.TooManyRequests => "Превышен лимит запросов к Simkl (429 Too Many Requests)",
                    _ => $"Ошибка сервиса Simkl: {(int)resp.StatusCode} {resp.ReasonPhrase}"
                });
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Таймаут соединения с Simkl (сервис не отвечает)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            ExternalApiLog.Failed(logger, Name, ex, "search/id?simkl=1");
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"Ошибка сети: {ex.Message}");
        }
    }

    private static ExternalMediaDto MapItem(SimklItem item, string type)
    {
        // Ratings ride along only when the request asked for extended=full, so this block is the
        // only place a score can come from. Falling back to the IMDb/MAL numbers would file their
        // rating under "Simkl", which the settings UI then shows as a Simkl score the user never gave.
        var simklRating = item.Ratings?.Simkl;
        var score = simklRating?.Rating;
        var ratings = new List<ExternalRatingDto>();

        if (score is > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Simkl",
                Rating = Math.Round(score.Value, 1),
                Votes = simklRating!.Votes
            });
        }

        var cover = !string.IsNullOrWhiteSpace(item.Poster)
            ? $"https://simkl.in/posters/{item.Poster}_m.webp"
            : null;

        var extId = item.Ids?.SimklId?.ToString(CultureInfo.InvariantCulture) ?? item.Title ?? "unknown";

        return new ExternalMediaDto
        {
            ExternalId = extId,
            ExternalSource = "Simkl",
            Title = item.Title ?? "Unknown",
            CoverUrl = cover,
            ReleaseYear = item.Year,
            Type = type,
            Rating = score,
            RatingVotes = simklRating?.Votes,
            Ratings = ratings
        };
    }

    private sealed class SimklItem
    {
        [JsonPropertyName("title")]
        public string? Title { get; set; }

        [JsonPropertyName("year")]
        public int? Year { get; set; }

        [JsonPropertyName("poster")]
        public string? Poster { get; set; }

        [JsonPropertyName("ids")]
        public SimklIds? Ids { get; set; }

        [JsonPropertyName("ratings")]
        public SimklRatings? Ratings { get; set; }
    }

    private sealed class SimklIds
    {
        /// <summary>
        /// The field is <c>simkl_id</c>, not <c>simkl</c>. Reading <c>simkl</c> always missed, so every
        /// item's ExternalId silently fell back to its title and nothing could be relinked by id.
        /// </summary>
        [JsonPropertyName("simkl_id")]
        public long? SimklId { get; set; }

        [JsonPropertyName("slug")]
        public string? Slug { get; set; }
    }

    private sealed class SimklRatings
    {
        [JsonPropertyName("simkl")]
        public SimklRatingItem? Simkl { get; set; }
    }

    private sealed class SimklRatingItem
    {
        [JsonPropertyName("rating")]
        public double? Rating { get; set; }

        [JsonPropertyName("votes")]
        public int? Votes { get; set; }
    }
}
