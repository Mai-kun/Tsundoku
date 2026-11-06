using System.Text.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Kitsu;

internal sealed record KitsuSearchResponse(List<KitsuData>? Data);
internal sealed record KitsuSingleResponse(KitsuData? Data);

/// <summary>Any list route the related links point at (genres, categories, castings, characters, staff).</summary>
internal sealed record KitsuRelatedResponse(List<KitsuRelatedRow>? Data, List<KitsuIncluded>? Included);

/// <summary>The media-relationships route (include=destination inlines the linked titles).</summary>
internal sealed record KitsuMediaRelationshipsResponse(
    List<KitsuRelationshipRow>? Data,
    List<KitsuIncluded>? Included);

internal sealed record KitsuData(string? Id, KitsuAttributes? Attributes, Dictionary<string, KitsuRelNode>? Relationships);

internal sealed record KitsuAttributes(
    [property: JsonPropertyName("canonicalTitle")] string? CanonicalTitle,
    [property: JsonPropertyName("titles")] Dictionary<string, string>? Titles,
    [property: JsonPropertyName("abbreviatedTitles")] List<string>? AbbreviatedTitles,
    [property: JsonPropertyName("synopsis")] string? Synopsis,
    [property: JsonPropertyName("averageRating")] string? AverageRating,
    [property: JsonPropertyName("userCount")] int? UserCount,
    [property: JsonPropertyName("startDate")] string? StartDate,
    [property: JsonPropertyName("endDate")] string? EndDate,
    [property: JsonPropertyName("status")] string? Status,
    [property: JsonPropertyName("posterImage")] KitsuPosterImage? PosterImage,
    [property: JsonPropertyName("episodeCount")] int? EpisodeCount,
    [property: JsonPropertyName("episodeLength")] int? EpisodeLength,
    [property: JsonPropertyName("chapterCount")] int? ChapterCount,
    [property: JsonPropertyName("volumeCount")] int? VolumeCount,
    [property: JsonPropertyName("subtype")] string? Subtype);

internal sealed record KitsuPosterImage(string? Large, string? Original);

/// <summary>A row of a related-list response (a casting, a character edge, a staff credit, a genre).</summary>
internal sealed record KitsuRelatedRow(string? Id, KitsuRelatedAttributes? Attributes, Dictionary<string, KitsuRelNode>? Relationships);

internal sealed record KitsuRelatedAttributes(
    [property: JsonPropertyName("role")] string? Role,
    [property: JsonPropertyName("voiceActor")] bool? VoiceActor,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("title")] string? Title);

/// <summary>A JSON:API relationship node: the related collection link plus the optional resource ref.</summary>
internal sealed record KitsuRelNode(KitsuRelLinks? Links, KitsuRelRef? Data);

internal sealed record KitsuRelLinks(
    [property: JsonPropertyName("related")] string? Related);

internal sealed record KitsuRelRef(string? Id, string? Type);

internal sealed record KitsuRelationshipRow(string? Id, KitsuRelatedAttributes? Attributes, Dictionary<string, KitsuRelNode>? Relationships);

/// <summary>
/// An inlined resource ("include=..."). Attributes stay raw: a character, a person and a related
/// media carry differently-shaped payloads, and each consumer reads its own fields.
/// </summary>
internal sealed record KitsuIncluded(string? Id, string? Type, JsonElement Attributes);
