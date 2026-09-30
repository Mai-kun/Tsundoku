using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Services.External;

public sealed class KitsuMetadataProvider(IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    public string Id => "kitsu";
    public string Name => "Kitsu";
    public string Description => "Anime ratings provider (community scores)";
    public IReadOnlyList<string> MediaTypes => ["anime"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Kitsu");
        try
        {
            var res = await client.GetFromJsonAsync<KitsuSearchResponse>(
                $"edge/anime?filter%5Btext%5D={Uri.EscapeDataString(query)}&page%5Blimit%5D=10", ct);

            if (res?.Data is not { Count: > 0 } data)
            {
                return [];
            }

            return data.ConvertAll(MapItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Kitsu");
        try
        {
            var res = await client.GetFromJsonAsync<KitsuSingleResponse>($"edge/anime/{Uri.EscapeDataString(externalId)}", ct);
            if (res?.Data is not null)
            {
                return MapItem(res.Data);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Fall back to title search
        }

        var results = await SearchAsync(title, ct);
        return results.FirstOrDefault(r => r.ExternalId == externalId) ?? (results.Count > 0 ? results[0] : null);
    }

    private static ExternalMediaDto MapItem(KitsuData item)
    {
        var attr = item.Attributes;
        var title = attr?.CanonicalTitle ?? "Unknown";
        double? rating = null;
        if (!string.IsNullOrWhiteSpace(attr?.AverageRating) &&
            double.TryParse(attr.AverageRating, System.Globalization.CultureInfo.InvariantCulture, out var score) &&
            score > 0)
        {
            rating = Math.Round(score / 10.0, 1);
        }

        List<ExternalRatingDto>? ratings = rating.HasValue
            ? [new ExternalRatingDto { Source = "Kitsu", Rating = rating.Value, Votes = attr?.UserCount }]
            : null;

        int? releaseYear = null;
        if (!string.IsNullOrWhiteSpace(attr?.StartDate) &&
            DateTime.TryParse(attr.StartDate, out var sDate))
        {
            releaseYear = sDate.Year;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.Id ?? string.Empty,
            ExternalSource = "Kitsu",
            Type = "anime",
            Title = title,
            Description = attr?.Synopsis,
            CoverUrl = attr?.PosterImage?.Large ?? attr?.PosterImage?.Original,
            TotalCount = attr?.EpisodeCount,
            RuntimeMinutes = attr?.EpisodeLength,
            Rating = rating,
            RatingVotes = attr?.UserCount,
            Ratings = ratings,
            ReleaseDate = attr?.StartDate,
            EndDate = attr?.EndDate,
            ReleaseYear = releaseYear,
            ReleaseStatus = attr?.Status
        };
    }

    private sealed record KitsuSearchResponse(List<KitsuData>? Data);
    private sealed record KitsuSingleResponse(KitsuData? Data);
    private sealed record KitsuData(string? Id, KitsuAttributes? Attributes);
    private sealed record KitsuAttributes(
        [property: JsonPropertyName("canonicalTitle")] string? CanonicalTitle,
        [property: JsonPropertyName("synopsis")] string? Synopsis,
        [property: JsonPropertyName("averageRating")] string? AverageRating,
        [property: JsonPropertyName("userCount")] int? UserCount,
        [property: JsonPropertyName("startDate")] string? StartDate,
        [property: JsonPropertyName("endDate")] string? EndDate,
        [property: JsonPropertyName("status")] string? Status,
        [property: JsonPropertyName("posterImage")] KitsuPosterImage? PosterImage,
        [property: JsonPropertyName("episodeCount")] int? EpisodeCount,
        [property: JsonPropertyName("episodeLength")] int? EpisodeLength);
    private sealed record KitsuPosterImage(string? Large, string? Original);
}
