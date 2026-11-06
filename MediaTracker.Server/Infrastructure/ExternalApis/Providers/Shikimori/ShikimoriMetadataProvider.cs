using System.Globalization;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Shikimori;

public sealed class ShikimoriMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "shikimori",
        Name: "Shikimori",
        Description: "Anime & manga metadata and community ratings provider",
        MediaTypes: ["anime", "manga", "book"],
        BaseAddress: "https://shikimori.io/api/",
        Priority: 2,
        UserAgent: "MediaTracker/1.0 (Tsundoku)");

    private readonly string _mediaType =
        serviceKey?.Contains("book", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.Contains("novel", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.Contains("ranobe", StringComparison.OrdinalIgnoreCase) is true
            ? "book"
            : (serviceKey?.Contains("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime");

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var cleaned = MediaTitleHelper.StripGarbageSuffixes(query);
        var effectiveQuery = !string.IsNullOrWhiteSpace(cleaned) ? cleaned : query;
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = _mediaType switch
        {
            "book" => $"mangas?kind=light_novel&search={Uri.EscapeDataString(effectiveQuery)}&limit=10",
            "manga" => $"mangas?search={Uri.EscapeDataString(effectiveQuery)}&limit=10",
            _ => $"animes?search={Uri.EscapeDataString(effectiveQuery)}&limit=10"
        };

        try
        {
            var items = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.ListShikimoriItem, ct);
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
        var endpoint = (_mediaType == "manga" || _mediaType == "book") ? $"mangas/{externalId}" : $"animes/{externalId}";

        try
        {
            var item = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.ShikimoriItem, ct);
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

        var author = item.Authors?.FirstOrDefault(a => !string.IsNullOrWhiteSpace(a.Russian) || !string.IsNullOrWhiteSpace(a.Name));
        var authorName = author is not null ? (!string.IsNullOrWhiteSpace(author.Russian) ? author.Russian : author.Name) : null;
        var isNovel = type == "book" || string.Equals(item.Kind, "light_novel", StringComparison.OrdinalIgnoreCase) || string.Equals(item.Kind, "novel", StringComparison.OrdinalIgnoreCase);

        var resolvedType = (type == "book" || isNovel) ? "book" : (type == "anime" ? "anime" : "manga");
        var mangaFormat = resolvedType == "book" ? "light_novel" : (resolvedType == "manga" ? "manga" : null);

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Shikimori",
            Title = !string.IsNullOrWhiteSpace(item.Russian) ? item.Russian : item.Name,
            OriginalTitle = item.Japanese?.FirstOrDefault(j => !string.IsNullOrWhiteSpace(j)) ?? item.Name,
            RomajiTitle = item.Name,
            CoverUrl = cover,
            Description = item.Description,
            Author = authorName,
            ReleaseYear = releaseYear,
            ReleaseDate = item.AiredOn,
            EndDate = item.ReleasedOn,
            ReleaseStatus = item.Status?.ToUpperInvariant(),
            Type = resolvedType,
            MangaFormat = mangaFormat,
            TotalCount = resolvedType == "anime" ? item.Episodes : (item.Chapters is > 0 ? item.Chapters : item.Volumes),
            Chapters = item.Chapters,
            Volumes = item.Volumes,
            Rating = score,
            Ratings = ratings,
            Synonyms = item.Synonyms is { Count: > 0 } syns ? [.. syns.Where(s => !string.IsNullOrWhiteSpace(s))] : null,
            Genres = item.Genres is { Count: > 0 }
                ? item.Genres
                    .Select(g => !string.IsNullOrWhiteSpace(g.Russian) ? g.Russian : g.Name)
                    .Where(g => !string.IsNullOrWhiteSpace(g))
                    .Select(g => g!)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList()
                : null
        };
    }
}
