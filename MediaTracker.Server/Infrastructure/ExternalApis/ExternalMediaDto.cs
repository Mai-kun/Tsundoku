using MediaTracker.Server.Domain.Rules;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

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

/// <summary>
/// One real season of a series. Sources that report a season tree (Kinopoisk) map to this instead of
/// flattening every episode into one list, which is what collapsed "Breaking Bad" into a single season.
/// </summary>
public sealed record ExternalSeasonDto
{
    public required int Number { get; init; }

    public string? Title { get; init; }

    public required int TotalEpisodes { get; init; }

    public IReadOnlyList<ExternalEpisodeDto>? Episodes { get; init; }
}

/// <summary>
/// One recommended title, normalised across providers. AniList answers in GraphQL, TMDb in REST, and
/// neither shape matches the other, so the tab renders this instead of a provider-specific row.
/// </summary>
public sealed record ExternalRecommendationDto(
    string Id,
    string Title,
    string? CoverUrl,
    double? Rating,
    string Source = "");

/// <summary>
/// A related title plus the relationship that produced it. The media payload reuses
/// <see cref="ExternalMediaDto"/> rather than repeating it: every field the Related tab renders
/// already lives there, so adding a second copy of them here would only create a second thing to keep
/// in sync.
/// </summary>
public sealed record ExternalRelationDto(string RelationType, ExternalMediaDto Media);

public sealed record ExternalMediaDto
{
    public required string ExternalId { get; init; }

    public required string Title { get; init; }

    public string? OriginalTitle { get; init; }

    public string? RomajiTitle { get; init; }

    public string? SteamAppId { get; init; }

    public string? CoverUrl { get; init; }

    public string? Description { get; init; }

    public int? ReleaseYear { get; init; }

    public string? ReleaseDate { get; init; }

    public string? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    /// <summary>Provider's own format label (MANGA, NOVEL, TV, MOVIE...). Null when it reports none.</summary>
    public string? Format { get; init; }

    public int? RuntimeMinutes { get; init; }

    public required string Type { get; init; }

    public string? Author { get; init; }

    public string? Studio { get; init; }

    public int? TotalCount { get; init; }

    public int? Chapters { get; init; }

    public int? Volumes { get; init; }

    /// <summary>One of the <see cref="MangaFormats"/> constants. Null when no source could tell.</summary>
    public string? MangaFormat { get; init; }

    public string? Platform { get; init; }

    public string? ExternalSource { get; init; }

    public double? Rating { get; init; }

    public int? RatingVotes { get; init; }

    public IReadOnlyList<ExternalRatingDto>? Ratings { get; init; }

    public IReadOnlyList<ExternalEpisodeDto>? Episodes { get; init; }

    /// <summary>Real per-season breakdown. Null for sources that only report a flat episode count.</summary>
    public IReadOnlyList<ExternalSeasonDto>? Seasons { get; init; }

    public IReadOnlyList<string>? Genres { get; init; }

    public IReadOnlyList<string>? Tags { get; init; }
}
