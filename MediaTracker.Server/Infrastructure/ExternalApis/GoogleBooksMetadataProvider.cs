using System.Diagnostics;
using System.Net;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class GoogleBooksMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "googlebooks",
        Name: "Google Books",
        Description: "Books metadata and ratings provider from Google",
        MediaTypes: ["book"],
        BaseAddress: "https://www.googleapis.com/books/v1/",
        RequiresApiKey: true,
        Priority: 2,
        Aliases: ["google"]);

    private string ApiKey => options.Value.GetKey(Id) ?? string.Empty;

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"volumes?q={Uri.EscapeDataString(query)}&maxResults=10&key={Uri.EscapeDataString(key)}";

        try
        {
            var res = await client.GetFromJsonAsync<GoogleBooksSearchResponse>(endpoint, ct);
            if (res?.Items is null || res.Items.Count == 0)
            {
                return [];
            }

            return res.Items.ConvertAll(MapItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"volumes/{Uri.EscapeDataString(externalId)}?key={Uri.EscapeDataString(key)}";

        try
        {
            var item = await client.GetFromJsonAsync<GoogleBookItem>(endpoint, ct);
            if (item is null)
            {
                return null;
            }

            return MapItem(item);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return new ConnectionTestResult(false, 0, "API key не указан");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            using var resp = await client.GetAsync(
                $"volumes?q=test&maxResults=1&key={Uri.EscapeDataString(key)}",
                HttpCompletionOption.ResponseHeadersRead,
                cts.Token);
            sw.Stop();

            if (resp.IsSuccessStatusCode)
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                resp.StatusCode switch
                {
                    HttpStatusCode.BadRequest => "Недействительный API-ключ Google Books (400 Bad Request)",
                    HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests => "Превышена квота или доступ запрещен (Google Books)",
                    _ => $"Ошибка Google Books: {(int)resp.StatusCode} {resp.ReasonPhrase}"
                });
        }
        catch (OperationCanceledException)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Таймаут соединения с Google Books");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"Ошибка сети: {ex.Message}");
        }
    }

    private static ExternalMediaDto MapItem(GoogleBookItem item)
    {
        var info = item.VolumeInfo;
        var cover = info?.ImageLinks?.Thumbnail ?? info?.ImageLinks?.SmallThumbnail;
        if (!string.IsNullOrWhiteSpace(cover) && cover.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
        {
            cover = "https://" + cover[7..];
        }

        double? rating = info?.AverageRating;
        int? votes = info?.RatingsCount;

        var ratings = new List<ExternalRatingDto>();
        if (rating is > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Google Books",
                Rating = Math.Round(rating.Value * 2, 1),
                Votes = votes
            });
        }

        int? releaseYear = null;
        if (!string.IsNullOrWhiteSpace(info?.PublishedDate) && DateTime.TryParse(info.PublishedDate, out var pubDate))
        {
            releaseYear = pubDate.Year;
        }

        var author = info?.Authors is { Count: > 0 } ? string.Join(", ", info.Authors) : null;

        return new ExternalMediaDto
        {
            ExternalId = item.Id,
            ExternalSource = "Google Books",
            Title = info?.Title ?? "Unknown",
            CoverUrl = cover,
            Description = info?.Description,
            ReleaseYear = releaseYear,
            ReleaseDate = info?.PublishedDate,
            Type = "book",
            Author = author,
            TotalCount = info?.PageCount,
            Rating = rating is > 0 ? rating.Value * 2 : null,
            RatingVotes = votes,
            Ratings = ratings
        };
    }

    private sealed class GoogleBooksSearchResponse
    {
        [JsonPropertyName("items")]
        public List<GoogleBookItem>? Items { get; set; }
    }

    private sealed class GoogleBookItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("volumeInfo")]
        public GoogleBookVolumeInfo? VolumeInfo { get; set; }
    }

    private sealed class GoogleBookVolumeInfo
    {
        [JsonPropertyName("title")]
        public string? Title { get; set; }

        [JsonPropertyName("authors")]
        public List<string>? Authors { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        [JsonPropertyName("publishedDate")]
        public string? PublishedDate { get; set; }

        [JsonPropertyName("pageCount")]
        public int? PageCount { get; set; }

        [JsonPropertyName("averageRating")]
        public double? AverageRating { get; set; }

        [JsonPropertyName("ratingsCount")]
        public int? RatingsCount { get; set; }

        [JsonPropertyName("imageLinks")]
        public GoogleBookImageLinks? ImageLinks { get; set; }
    }

    private sealed class GoogleBookImageLinks
    {
        [JsonPropertyName("thumbnail")]
        public string? Thumbnail { get; set; }

        [JsonPropertyName("smallThumbnail")]
        public string? SmallThumbnail { get; set; }
    }
}
