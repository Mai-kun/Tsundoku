using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class KitsuMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "kitsu",
        Name: "Kitsu",
        Description: "Anime and Manga ratings provider (community scores)",
        MediaTypes: ["anime", "manga"],
        BaseAddress: "https://kitsu.io/api/",
        Priority: 3);

    private readonly string mediaType = serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime";

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        try
        {
            var res = await client.GetFromJsonAsync<KitsuSearchResponse>(
                $"edge/{mediaType}?filter%5Btext%5D={Uri.EscapeDataString(query)}&page%5Blimit%5D=10", ct);

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

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        try
        {
            var res = await client.GetFromJsonAsync<KitsuSingleResponse>($"edge/{mediaType}/{Uri.EscapeDataString(externalId)}", ct);
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

    private ExternalMediaDto MapItem(KitsuData item)
    {
        var attr = item.Attributes;
        var title = attr?.CanonicalTitle ?? "Unknown";
        double? rating = null;
        if (!string.IsNullOrWhiteSpace(attr?.AverageRating) &&
            double.TryParse(attr.AverageRating, NumberStyles.Any, CultureInfo.InvariantCulture, out var score) &&
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
            Type = mediaType,
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
            ReleaseStatus = attr?.Status,
            Genres = ExtractGenres(attr?.Categories, attr?.Genres)
        };
    }

    private static List<string>? ExtractGenres(JsonElement? categories, JsonElement? genres)
    {
        var list = new List<string>();
        ExtractFromJson(categories, list);
        ExtractFromJson(genres, list);
        return list.Count > 0 ? list.Distinct(StringComparer.OrdinalIgnoreCase).ToList() : null;
    }

    private static void ExtractFromJson(JsonElement? element, List<string> target)
    {
        if (element is not { ValueKind: not JsonValueKind.Undefined and not JsonValueKind.Null } el)
        {
            return;
        }

        if (el.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in el.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.String && item.GetString() is { } str && !string.IsNullOrWhiteSpace(str))
                {
                    target.Add(str);
                }
                else if (item.ValueKind == JsonValueKind.Object)
                {
                    if ((item.TryGetProperty("title", out var titleProp) || item.TryGetProperty("name", out titleProp) || item.TryGetProperty("genre", out titleProp))
                        && titleProp.ValueKind == JsonValueKind.String
                        && titleProp.GetString() is { } name
                        && !string.IsNullOrWhiteSpace(name))
                    {
                        target.Add(name);
                    }
                }
            }
        }
        else if (el.ValueKind == JsonValueKind.String && el.GetString() is { } s && !string.IsNullOrWhiteSpace(s))
        {
            target.AddRange(s.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        }
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
        [property: JsonPropertyName("episodeLength")] int? EpisodeLength,
        [property: JsonPropertyName("categories")] JsonElement? Categories,
        [property: JsonPropertyName("genres")] JsonElement? Genres);
    private sealed record KitsuPosterImage(string? Large, string? Original);
}
