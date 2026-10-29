using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using MediaTracker.Server.Domain.Rules;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class MdMangaListResponse
{
    [JsonPropertyName("data")]
    public List<MdMangaData>? Data { get; set; }
}

internal sealed class MdMangaSingleResponse
{
    [JsonPropertyName("data")]
    public MdMangaData? Data { get; set; }
}

internal sealed class MdMangaData
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("attributes")]
    public MdMangaAttributes? Attributes { get; set; }

    [JsonPropertyName("relationships")]
    public List<MdRelationship>? Relationships { get; set; }
}

internal sealed class MdMangaAttributes
{
    [JsonPropertyName("title")]
    public Dictionary<string, string>? Title { get; set; }

    [JsonPropertyName("altTitles")]
    public List<Dictionary<string, string>>? AltTitles { get; set; }

    [JsonPropertyName("description")]
    public Dictionary<string, string>? Description { get; set; }

    [JsonPropertyName("lastVolume")]
    public string? LastVolume { get; set; }

    [JsonPropertyName("lastChapter")]
    public string? LastChapter { get; set; }

    [JsonPropertyName("status")]
    public string? Status { get; set; }

    [JsonPropertyName("originalLanguage")]
    public string? OriginalLanguage { get; set; }

    [JsonPropertyName("year")]
    public int? Year { get; set; }

    [JsonPropertyName("createdAt")]
    public DateTime? CreatedAt { get; set; }

    [JsonPropertyName("tags")]
    public List<MdTag>? Tags { get; set; }
}

internal sealed class MdTag
{
    [JsonPropertyName("attributes")]
    public MdTagAttributes? Attributes { get; set; }
}

internal sealed class MdTagAttributes
{
    [JsonPropertyName("name")]
    public Dictionary<string, string>? Name { get; set; }
}

internal sealed class MdRelationship
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("attributes")]
    public JsonElement? Attributes { get; set; }

    /// <summary>MangaDex relation vocabulary: sequel, prequel, spin_off, side_story... A sibling of
    /// <c>type</c> on the relation object, not a property inside <c>attributes</c>.</summary>
    [JsonPropertyName("related")]
    public string? Related { get; set; }
}

internal sealed class MdStatisticsResponse
{
    [JsonPropertyName("statistics")]
    public Dictionary<string, MdMangaStatistics>? Statistics { get; set; }
}

internal sealed class MdMangaStatistics
{
    [JsonPropertyName("rating")]
    public MdRating? Rating { get; set; }

    [JsonPropertyName("follows")]
    public int? Follows { get; set; }
}

internal sealed class MdRating
{
    [JsonPropertyName("average")]
    public double? Average { get; set; }

    [JsonPropertyName("bayesian")]
    public double? Bayesian { get; set; }

    [JsonPropertyName("distribution")]
    public Dictionary<string, int>? Distribution { get; set; }
}

internal sealed class MdCoverListResponse
{
    [JsonPropertyName("data")]
    public List<MdCoverData>? Data { get; set; }
}

internal sealed class MdCoverData
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("attributes")]
    public MdCoverAttributes? Attributes { get; set; }
}

internal sealed class MdCoverAttributes
{
    [JsonPropertyName("volume")]
    public string? Volume { get; set; }

    [JsonPropertyName("fileName")]
    public string? FileName { get; set; }

    [JsonPropertyName("locale")]
    public string? Locale { get; set; }
}

