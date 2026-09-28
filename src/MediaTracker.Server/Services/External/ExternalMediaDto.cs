namespace MediaTracker.Server.Services.External;

public sealed record ExternalRatingDto
{
    public required string Source { get; init; }
    public required double Rating { get; init; }
    public int? Votes { get; init; }
}

public sealed record ExternalEpisodeDto
{
    public int Number { get; init; }
    public required string Title { get; init; }
    public string? AirDate { get; init; }
}

public sealed record ExternalMediaDto
{
    public required string ExternalId { get; init; }

    public required string Title { get; init; }

    public string? OriginalTitle { get; init; }

    public string? RomajiTitle { get; init; }

    public string? CoverUrl { get; init; }

    public string? Description { get; init; }

    public int? ReleaseYear { get; init; }
 
    public string? ReleaseDate { get; init; }

    public string? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    public int? RuntimeMinutes { get; init; }

    public required string Type { get; init; }

    public string? Author { get; init; }

    public string? Studio { get; init; }

    public int? TotalCount { get; init; }

    public string? Platform { get; init; }

    public string? ExternalSource { get; init; }

    public double? Rating { get; init; }

    public int? RatingVotes { get; init; }

    public IReadOnlyList<ExternalRatingDto>? Ratings { get; init; }

    public IReadOnlyList<ExternalEpisodeDto>? Episodes { get; init; }
}
