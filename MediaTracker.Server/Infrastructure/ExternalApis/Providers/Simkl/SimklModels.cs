using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class SimklItem
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("year")]
    public int? Year { get; set; }

    [JsonPropertyName("poster")]
    public string? Poster { get; set; }

    [JsonPropertyName("ids")]
    public SimklIds? Ids { get; set; }

    [JsonPropertyName("ratings")]
    public SimklRatings? Ratings { get; set; }

    [JsonPropertyName("genres")]
    public List<string>? Genres { get; set; }
}

internal sealed class SimklIds
{
    /// <summary>
    /// The field is <c>simkl_id</c>, not <c>simkl</c>. Reading <c>simkl</c> always missed, so every
    /// item's ExternalId silently fell back to its title and nothing could be relinked by id.
    /// </summary>
    [JsonPropertyName("simkl_id")]
    public long? SimklId { get; set; }

    [JsonPropertyName("slug")]
    public string? Slug { get; set; }
}

internal sealed class SimklRatings
{
    [JsonPropertyName("simkl")]
    public SimklRatingItem? Simkl { get; set; }
}

internal sealed class SimklRatingItem
{
    [JsonPropertyName("rating")]
    public double? Rating { get; set; }

    [JsonPropertyName("votes")]
    public int? Votes { get; set; }
}
