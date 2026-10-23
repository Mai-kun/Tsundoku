using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class MuSearchResponse
{
    [JsonPropertyName("results")]
    public List<MuSearchResult>? Results { get; set; }
}

internal sealed class MuSearchResult
{
    [JsonPropertyName("record")]
    public MuSeriesRecord? Record { get; set; }
}

internal sealed class MuRating
{
    [JsonPropertyName("bayesian_rating")]
    public double? BayesianRating { get; set; }

    [JsonPropertyName("rating")]
    public double? Rating { get; set; }

    [JsonPropertyName("votes")]
    public int? Votes { get; set; }
}

internal sealed class MuSeriesRecord
{
    [JsonPropertyName("series_id")]
    public long SeriesId { get; set; }

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("year")]
    public string? Year { get; set; }

    [JsonPropertyName("bayesian_rating")]
    public double? BayesianRating { get; set; }

    [JsonPropertyName("rating_votes")]
    public int? RatingVotes { get; set; }

    [JsonPropertyName("rating")]
    public MuRating? Rating { get; set; }

    [JsonPropertyName("latest_chapter")]
    public int? LatestChapter { get; set; }

    [JsonPropertyName("image")]
    public MuImage? Image { get; set; }

    [JsonPropertyName("authors")]
    public List<MuAuthor>? Authors { get; set; }

    [JsonPropertyName("associated")]
    public List<MuAssociatedTitle>? Associated { get; set; }

    [JsonPropertyName("genres")]
    public List<MuGenre>? Genres { get; set; }
}

internal sealed class MuGenre
{
    [JsonPropertyName("genre")]
    public string? Genre { get; set; }
}

internal sealed class MuImage
{
    [JsonPropertyName("url")]
    public MuImageUrl? Url { get; set; }
}

internal sealed class MuImageUrl
{
    [JsonPropertyName("original")]
    public string? Original { get; set; }

    [JsonPropertyName("thumb")]
    public string? Thumb { get; set; }
}

internal sealed class MuAuthor
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }
}

internal sealed class MuAssociatedTitle
{
    [JsonPropertyName("title")]
    public string? Title { get; set; }
}
