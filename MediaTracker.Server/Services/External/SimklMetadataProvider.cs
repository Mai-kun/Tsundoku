using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Services.External;

public sealed class SimklMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null) : IMetadataProvider
{
    public string Id => "simkl";
    public string Name => "Simkl";
    public string Description => "Anime, TV shows and movies metadata & ratings tracking service";
    public IReadOnlyList<string> MediaTypes => ["anime", "movie", "tvshow"];
    public bool RequiresApiKey => true;

    private readonly string _mediaType = serviceKey?.StartsWith("anime", StringComparison.OrdinalIgnoreCase) is true ? "anime"
        : serviceKey?.StartsWith("movie", StringComparison.OrdinalIgnoreCase) is true ? "movie"
        : serviceKey?.StartsWith("tvshow", StringComparison.OrdinalIgnoreCase) is true ? "tvshow"
        : "anime";

    private string ClientId => options.Value.GetKey(Id) ?? string.Empty;

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var clientId = ClientId;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return [];
        }

        var client = httpClientFactory.CreateClient("Simkl");
        var simklType = _mediaType switch
        {
            "movie" => "movies",
            "tvshow" => "tv",
            _ => "anime"
        };

        var endpoint = $"search/{simklType}?q={Uri.EscapeDataString(query)}&client_id={Uri.EscapeDataString(clientId)}&app-name=mediatracker&app-version=1.0";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.TryAddWithoutValidation("simkl-api-key", clientId);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                return [];
            }

            var items = await resp.Content.ReadFromJsonAsync<List<SimklItem>>(cancellationToken: ct);
            if (items is null || items.Count == 0)
            {
                return [];
            }

            return items.ConvertAll(item => MapItem(item, _mediaType));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var results = await SearchAsync(!string.IsNullOrWhiteSpace(title) ? title : externalId, ct);
        return results.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
               ?? (results.Count > 0 ? results[0] : null);
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var clientId = ClientId;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return new ConnectionTestResult(false, 0, "Client ID не указан");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient("Simkl");
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            using var req = new HttpRequestMessage(
                HttpMethod.Get,
                $"tv/17465?client_id={Uri.EscapeDataString(clientId)}&app-name=mediatracker&app-version=1.0");
            req.Headers.TryAddWithoutValidation("simkl-api-key", clientId);

            using var resp = await client.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
            sw.Stop();

            if (resp.IsSuccessStatusCode)
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

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
                    HttpStatusCode.Unauthorized => "Неверный Client ID (401 Unauthorized)",
                    HttpStatusCode.Forbidden => "Доступ запрещен сервисом Simkl (403 Forbidden)",
                    HttpStatusCode.NotFound => "Эндпоинт не найден (404 Not Found)",
                    HttpStatusCode.TooManyRequests => "Превышен лимит запросов к Simkl (429 Too Many Requests)",
                    _ => $"Ошибка сервиса Simkl: {(int)resp.StatusCode} {resp.ReasonPhrase}"
                });
        }
        catch (OperationCanceledException)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Таймаут соединения с Simkl (сервис не отвечает)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"Ошибка сети: {ex.Message}");
        }
    }

    private static ExternalMediaDto MapItem(SimklItem item, string type)
    {
        double? score = item.Ratings?.Simkl?.Rating ?? item.Ratings?.Imdb?.Rating ?? item.Ratings?.Mal?.Rating;
        var ratings = new List<ExternalRatingDto>();

        if (score.HasValue && score.Value > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Simkl",
                Rating = Math.Round(score.Value, 1),
                Votes = item.Ratings?.Simkl?.Votes
            });
        }

        var cover = !string.IsNullOrWhiteSpace(item.Poster)
            ? $"https://simkl.in/posters/{item.Poster}_m.webp"
            : null;

        var extId = item.Ids?.Simkl?.ToString(CultureInfo.InvariantCulture) ?? item.Title ?? "unknown";

        return new ExternalMediaDto
        {
            ExternalId = extId,
            ExternalSource = "Simkl",
            Title = item.Title ?? "Unknown",
            CoverUrl = cover,
            ReleaseYear = item.Year,
            Type = type,
            Rating = score,
            RatingVotes = item.Ratings?.Simkl?.Votes,
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
        [JsonPropertyName("simkl")]
        public long? Simkl { get; set; }

        [JsonPropertyName("slug")]
        public string? Slug { get; set; }
    }

    private sealed class SimklRatings
    {
        [JsonPropertyName("simkl")]
        public SimklRatingItem? Simkl { get; set; }

        [JsonPropertyName("imdb")]
        public SimklRatingItem? Imdb { get; set; }

        [JsonPropertyName("mal")]
        public SimklRatingItem? Mal { get; set; }
    }

    private sealed class SimklRatingItem
    {
        [JsonPropertyName("rating")]
        public double? Rating { get; set; }

        [JsonPropertyName("votes")]
        public int? Votes { get; set; }
    }
}
