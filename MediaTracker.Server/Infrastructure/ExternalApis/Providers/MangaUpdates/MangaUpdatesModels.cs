using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.MangaUpdates;

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

    /// <summary>MangaUpdates' origin label: Manga, Manhwa, Manhua, OEL (Original English Language)...</summary>
    [JsonPropertyName("type")]
    public string? Type { get; set; }

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

    /// <summary>The 3–5 curated genres — the only list that belongs in the genres block.</summary>
    [JsonPropertyName("genres")]
    public List<MuGenre>? Genres { get; set; }

    /// <summary>
    /// The large user-voted category list (tropes, themes, demographics — often dozens of rows).
    /// Kept off Genres on purpose; at most the top few belong in Tags.
    /// </summary>
    [JsonPropertyName("categories")]
    public List<MuCategory>? Categories { get; set; }

    /// <summary>Inline neighbour list of the details answer; the source for native relations.</summary>
    [JsonPropertyName("related_series")]
    public List<MuRelatedSeries>? RelatedSeries { get; set; }
}

internal sealed class MuGenre
{
    [JsonPropertyName("genre")]
    public string? Genre { get; set; }
}

internal sealed class MuCategory
{
    [JsonPropertyName("category")]
    public string? Category { get; set; }
}

internal sealed class MuRelatedSeries
{
    [JsonPropertyName("relation_type")]
    public string? RelationType { get; set; }

    [JsonPropertyName("related_series_id")]
    public long RelatedSeriesId { get; set; }

    [JsonPropertyName("related_series_name")]
    public string? RelatedSeriesName { get; set; }
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

/// <summary>POST /v1/series/search request body.</summary>
internal sealed record MuSearchRequest(string Search, string Stype, int Perpage);
