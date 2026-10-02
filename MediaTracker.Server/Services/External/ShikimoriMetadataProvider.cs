using System.Globalization;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class ShikimoriMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "shikimori",
        Name: "Shikimori",
        Description: "Anime & manga metadata and community ratings provider",
        MediaTypes: ["anime", "manga"],
        BaseAddress: "https://shikimori.io/api/",
        Priority: 2,
        UserAgent: "MediaTracker/1.0 (Tsundoku)");

    private readonly string _mediaType = serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime";

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = _mediaType == "manga"
            ? $"mangas?search={Uri.EscapeDataString(query)}&limit=10"
            : $"animes?search={Uri.EscapeDataString(query)}&limit=10";

        try
        {
            var items = await client.GetFromJsonAsync<List<ShikimoriItem>>(endpoint, ct);
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

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = _mediaType == "manga" ? $"mangas/{externalId}" : $"animes/{externalId}";

        try
        {
            var item = await client.GetFromJsonAsync<ShikimoriItem>(endpoint, ct);
            if (item is null)
            {
                return null;
            }

            return MapItem(item, _mediaType);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    private static ExternalMediaDto MapItem(ShikimoriItem item, string type)
    {
        var cover = item.Image?.Original ?? item.Image?.Preview;
        if (!string.IsNullOrWhiteSpace(cover) && cover.StartsWith('/'))
        {
            cover = $"https://shikimori.io{cover}";
        }

        double? score = null;
        if (!string.IsNullOrWhiteSpace(item.Score) && double.TryParse(item.Score, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedScore) && parsedScore > 0)
        {
            score = parsedScore;
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Shikimori",
                Rating = Math.Round(score.Value, 1),
                Votes = null
            });
        }

        int? releaseYear = null;
        if (!string.IsNullOrWhiteSpace(item.AiredOn) && DateTime.TryParse(item.AiredOn, out var airedDate))
        {
            releaseYear = airedDate.Year;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Shikimori",
            Title = !string.IsNullOrWhiteSpace(item.Russian) ? item.Russian : item.Name,
            OriginalTitle = item.Name,
            RomajiTitle = item.Name,
            CoverUrl = cover,
            Description = item.Description,
            ReleaseYear = releaseYear,
            ReleaseDate = item.AiredOn,
            EndDate = item.ReleasedOn,
            ReleaseStatus = item.Status?.ToUpperInvariant(),
            Type = type,
            TotalCount = type == "anime" ? item.Episodes : (item.Chapters is > 0 ? item.Chapters : item.Volumes),
            Chapters = item.Chapters,
            Volumes = item.Volumes,
            Rating = score,
            Ratings = ratings
        };
    }

    private sealed class ShikimoriItem
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("russian")]
        public string? Russian { get; set; }

        [JsonPropertyName("image")]
        public ShikimoriImage? Image { get; set; }

        [JsonPropertyName("score")]
        public string? Score { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("episodes")]
        public int? Episodes { get; set; }

        [JsonPropertyName("chapters")]
        public int? Chapters { get; set; }

        [JsonPropertyName("volumes")]
        public int? Volumes { get; set; }

        [JsonPropertyName("aired_on")]
        public string? AiredOn { get; set; }

        [JsonPropertyName("released_on")]
        public string? ReleasedOn { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }
    }

    private sealed class ShikimoriImage
    {
        [JsonPropertyName("original")]
        public string? Original { get; set; }

        [JsonPropertyName("preview")]
        public string? Preview { get; set; }
    }
}
