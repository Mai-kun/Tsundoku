using System.Diagnostics;
using System.Globalization;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Services.External;

public sealed class KinopoiskMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null) : IMetadataProvider
{
    public string Id => "kinopoisk";
    public string Name => "Кинопоиск (Kinopoisk)";
    public string Description => "Russian and international movies, TV series metadata & ratings";
    public IReadOnlyList<string> MediaTypes => ["movie", "tvshow"];
    public bool RequiresApiKey => true;

    private readonly string _mediaType = serviceKey?.StartsWith("tvshow", StringComparison.OrdinalIgnoreCase) is true ? "tvshow" : "movie";
    private string ApiKey => options.Value.GetKey(Id) ?? string.Empty;

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key)) return [];

        var client = httpClientFactory.CreateClient("Kinopoisk");
        var endpoint = $"v2.1/films/search-by-keyword?keyword={Uri.EscapeDataString(query)}&page=1";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode) return [];

            var body = await resp.Content.ReadFromJsonAsync<KinopoiskSearchResponse>(ct);
            if (body?.Films is null || body.Films.Count == 0) return [];

            return body.Films.ConvertAll(f => MapItem(f, _mediaType));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key)) return null;

        var client = httpClientFactory.CreateClient("Kinopoisk");
        var endpoint = $"v2.2/films/{Uri.EscapeDataString(externalId)}";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode) return null;

            var item = await resp.Content.ReadFromJsonAsync<KinopoiskDetailItem>(ct);
            if (item is null) return null;

            return MapDetailItem(item, _mediaType);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return new ConnectionTestResult(false, 0, "API key (X-API-KEY) is required");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient("Kinopoisk");
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            using var req = new HttpRequestMessage(HttpMethod.Get, "v2.1/films/search-by-keyword?keyword=test&page=1");
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, cts.Token);
            sw.Stop();
            if (resp.IsSuccessStatusCode)
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"HTTP {(int)resp.StatusCode} {resp.ReasonPhrase}");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }

    private static ExternalMediaDto MapItem(KinopoiskFilmItem item, string type)
    {
        double? score = null;
        if (!string.IsNullOrWhiteSpace(item.Rating) && double.TryParse(item.Rating.TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) && parsed > 0)
        {
            score = parsed;
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Kinopoisk",
                Rating = Math.Round(score.Value, 1),
                Votes = item.RatingVoteCount
            });
        }

        int? year = null;
        if (!string.IsNullOrWhiteSpace(item.Year) && int.TryParse(item.Year, out var y))
        {
            year = y;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.FilmId.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Kinopoisk",
            Title = !string.IsNullOrWhiteSpace(item.NameRu) ? item.NameRu : (item.NameEn ?? "Unknown"),
            OriginalTitle = item.NameEn,
            CoverUrl = item.PosterUrlPreview ?? item.PosterUrl,
            Description = item.Description,
            ReleaseYear = year,
            Type = type,
            Rating = score,
            RatingVotes = item.RatingVoteCount,
            Ratings = ratings
        };
    }

    private static ExternalMediaDto MapDetailItem(KinopoiskDetailItem item, string type)
    {
        double? score = item.RatingKinopoisk ?? item.RatingImdb;
        var ratings = new List<ExternalRatingDto>();

        if (score.HasValue && score.Value > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Kinopoisk",
                Rating = Math.Round(score.Value, 1),
                Votes = item.RatingKinopoiskVoteCount
            });
        }

        return new ExternalMediaDto
        {
            ExternalId = item.KinopoiskId.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Kinopoisk",
            Title = !string.IsNullOrWhiteSpace(item.NameRu) ? item.NameRu : (item.NameOriginal ?? item.NameEn ?? "Unknown"),
            OriginalTitle = item.NameOriginal ?? item.NameEn,
            CoverUrl = item.PosterUrlPreview ?? item.PosterUrl,
            Description = item.Description,
            ReleaseYear = item.Year,
            Type = type,
            Rating = score,
            RatingVotes = item.RatingKinopoiskVoteCount,
            Ratings = ratings
        };
    }

    private sealed class KinopoiskSearchResponse
    {
        [JsonPropertyName("films")]
        public List<KinopoiskFilmItem>? Films { get; set; }
    }

    private sealed class KinopoiskFilmItem
    {
        [JsonPropertyName("filmId")]
        public long FilmId { get; set; }

        [JsonPropertyName("nameRu")]
        public string? NameRu { get; set; }

        [JsonPropertyName("nameEn")]
        public string? NameEn { get; set; }

        [JsonPropertyName("year")]
        public string? Year { get; set; }

        [JsonPropertyName("rating")]
        public string? Rating { get; set; }

        [JsonPropertyName("ratingVoteCount")]
        public int? RatingVoteCount { get; set; }

        [JsonPropertyName("posterUrl")]
        public string? PosterUrl { get; set; }

        [JsonPropertyName("posterUrlPreview")]
        public string? PosterUrlPreview { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }
    }

    private sealed class KinopoiskDetailItem
    {
        [JsonPropertyName("kinopoiskId")]
        public long KinopoiskId { get; set; }

        [JsonPropertyName("nameRu")]
        public string? NameRu { get; set; }

        [JsonPropertyName("nameEn")]
        public string? NameEn { get; set; }

        [JsonPropertyName("nameOriginal")]
        public string? NameOriginal { get; set; }

        [JsonPropertyName("posterUrl")]
        public string? PosterUrl { get; set; }

        [JsonPropertyName("posterUrlPreview")]
        public string? PosterUrlPreview { get; set; }

        [JsonPropertyName("ratingKinopoisk")]
        public double? RatingKinopoisk { get; set; }

        [JsonPropertyName("ratingKinopoiskVoteCount")]
        public int? RatingKinopoiskVoteCount { get; set; }

        [JsonPropertyName("ratingImdb")]
        public double? RatingImdb { get; set; }

        [JsonPropertyName("year")]
        public int? Year { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }
    }
}
