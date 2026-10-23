using System.Globalization;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class SteamStoreSearchResponse
{
    [JsonPropertyName("items")]
    public List<SteamSearchItem>? Items { get; set; }
}

internal sealed class SteamSearchItem
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("tiny_image")]
    public string? TinyImage { get; set; }

    [JsonPropertyName("metascore")]
    public string? Metascore { get; set; }
}

internal sealed class SteamAppDetailsWrapper
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("data")]
    public SteamAppDetails? Data { get; set; }
}

internal sealed class SteamAppDetails
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("short_description")]
    public string? ShortDescription { get; set; }

    [JsonPropertyName("detailed_description")]
    public string? DetailedDescription { get; set; }

    [JsonPropertyName("header_image")]
    public string? HeaderImage { get; set; }

    [JsonPropertyName("developers")]
    public List<string>? Developers { get; set; }

    [JsonPropertyName("release_date")]
    public SteamReleaseDate? ReleaseDate { get; set; }

    [JsonPropertyName("genres")]
    public List<SteamGenre>? Genres { get; set; }

    [JsonPropertyName("metacritic")]
    public SteamMetacritic? Metacritic { get; set; }
}

internal sealed class SteamGenre
{
    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }
}

internal sealed class SteamReleaseDate
{
    [JsonPropertyName("date")]
    public string? Date { get; set; }

    [JsonPropertyName("coming_soon")]
    public bool ComingSoon { get; set; }
}

internal sealed class SteamMetacritic
{
    [JsonPropertyName("score")]
    public double? Score { get; set; }
}

internal sealed class SteamReviewsResponse
{
    [JsonPropertyName("query_summary")]
    public SteamReviewSummary? QuerySummary { get; set; }
}

internal sealed class SteamReviewSummary
{
    [JsonPropertyName("total_reviews")]
    public int TotalReviews { get; set; }

    [JsonPropertyName("total_positive")]
    public int TotalPositive { get; set; }
}
