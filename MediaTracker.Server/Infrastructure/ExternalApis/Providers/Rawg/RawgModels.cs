using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed record RawgResponse(List<RawgGame>? Results);

internal sealed record RawgGame(
    long Id,
    string? Name,
    [property: JsonPropertyName("name_original")] string? NameOriginal,
    string? Released,
    bool? Tba,
    [property: JsonPropertyName("background_image")] string? BackgroundImage,
    [property: JsonPropertyName("description_raw")] string? DescriptionRaw,
    string? Description,
    double? Rating,
    [property: JsonPropertyName("ratings_count")] int? RatingsCount,
    [property: JsonPropertyName("parent_platforms")] List<RawgParentPlatform>? ParentPlatforms,
    [property: JsonPropertyName("genres")] List<RawgGenre>? Genres,
    [property: JsonPropertyName("stores")] List<RawgGameStoreWrapper>? Stores,
    // Present in the details payload only; search results leave it null.
    [property: JsonPropertyName("developers")] List<RawgNamedEntity>? Developers);

internal sealed record RawgGameStoreWrapper(
    [property: JsonPropertyName("url")] string? Url,
    [property: JsonPropertyName("store")] RawgStoreInfo? Store);

internal sealed record RawgStoreInfo(
    [property: JsonPropertyName("id")] long? Id,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("slug")] string? Slug,
    [property: JsonPropertyName("domain")] string? Domain,
    [property: JsonPropertyName("url")] string? Url);

internal sealed record RawgStoresResponse(List<RawgStoreLink>? Results);

internal sealed record RawgStoreLink(
    [property: JsonPropertyName("url")] string? Url);

internal sealed record RawgGenre(string? Name);

internal sealed record RawgNamedEntity(string? Name);

internal sealed record RawgParentPlatform(RawgPlatform? Platform);

internal sealed record RawgPlatform(string? Name);

internal sealed class SteamAppDetailsRoot
{
    [JsonPropertyName("data")]
    public SteamAppDetailsData? Data { get; set; }
}

internal sealed class SteamAppDetailsData
{
    [JsonPropertyName("achievements")]
    public SteamAchievementsBlock? Achievements { get; set; }
}

internal sealed class SteamAchievementsBlock
{
    [JsonPropertyName("total")]
    public int Total { get; set; }

    [JsonPropertyName("highlighted")]
    public List<SteamAchievementItem>? Highlighted { get; set; }
}

internal sealed class SteamAchievementItem
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("path")]
    public string? Path { get; set; }

    [JsonPropertyName("localized_name")]
    public string? LocalizedName { get; set; }
}

internal sealed class RawgSearchRoot
{
    [JsonPropertyName("results")]
    public List<RawgSearchResultItem>? Results { get; set; }
}

internal sealed class RawgSeriesRoot
{
    [JsonPropertyName("results")]
    public List<RawgSeriesItem>? Results { get; set; }
}

internal sealed class RawgDetailRoot
{
    [JsonPropertyName("genres")]
    public List<RawgDetailGenre>? Genres { get; set; }
}

internal sealed class RawgDetailGenre
{
    [JsonPropertyName("id")]
    public long Id { get; set; }
}

internal sealed class RawgAchievementsRoot
{
    [JsonPropertyName("count")]
    public int Count { get; set; }

    [JsonPropertyName("results")]
    public List<RawgAchievementResultItem>? Results { get; set; }
}

internal sealed class RawgAchievementResultItem
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("image")]
    public string? Image { get; set; }
}

internal sealed class RawgSearchResultItem
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("background_image")]
    public string? BackgroundImage { get; set; }

    [JsonPropertyName("released")]
    public string? Released { get; set; }

    [JsonPropertyName("rating")]
    public double? Rating { get; set; }
}

internal sealed class RawgSeriesItem
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("background_image")]
    public string? BackgroundImage { get; set; }

    [JsonPropertyName("released")]
    public string? Released { get; set; }

    [JsonPropertyName("rating")]
    public double? Rating { get; set; }
}
