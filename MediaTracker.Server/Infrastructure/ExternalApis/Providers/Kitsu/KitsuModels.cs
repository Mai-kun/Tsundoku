using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed record KitsuSearchResponse(List<KitsuData>? Data);
internal sealed record KitsuSingleResponse(KitsuData? Data);
internal sealed record KitsuData(string? Id, KitsuAttributes? Attributes);
internal sealed record KitsuAttributes(
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
internal sealed record KitsuPosterImage(string? Large, string? Original);
