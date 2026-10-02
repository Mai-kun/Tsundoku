namespace MediaTracker.Server.Services.External;

/// <summary>
/// Collapses the per-source manga origin signals into the four buckets the UI shows. The sources
/// disagree on purpose-free wording, so the mapping lives here instead of in each provider: AniList
/// files OEL manga under JP (which would read as plain "манга") while MangaDex reports the original
/// language, which is the only signal that actually identifies OEL.
/// </summary>
public static class MangaFormats
{
    public const string Manga = "manga";
    public const string Manhwa = "manhwa";
    public const string Manhua = "manhua";
    public const string Oel = "oel";

    /// <summary>AniList <c>countryOfOrigin</c>: KR manhwa, CN manhua, JP manga.</summary>
    public static string? FromCountryOfOrigin(string? country) =>
        Normalize(country) switch
        {
            "KR" => Manhwa,
            "CN" => Manhua,
            "JP" => Manga,
            _ => null,
        };

    /// <summary>MangaDex <c>originalLanguage</c>. "en" is the OEL signal the other sources lack.</summary>
    public static string? FromOriginalLanguage(string? language) =>
        Normalize(language) switch
        {
            "EN" => Oel,
            "KO" => Manhwa,
            "ZH" => Manhua,
            "JA" => Manga,
            _ => null,
        };

    /// <summary>
    /// OEL outranks everything because it is the only verdict a source can be more specific about:
    /// AniList reports a plain "manga" for titles MangaDex knows are original English. Everything
    /// else keeps the primary source's word, which is the one the user picked the entry from.
    /// </summary>
    public static string? Pick(string? primary, string? fallback) =>
        string.Equals(fallback, Oel, StringComparison.Ordinal) ? Oel : FirstNonEmpty(primary, fallback);

    private static string? FirstNonEmpty(string? primary, string? fallback) =>
        !string.IsNullOrWhiteSpace(primary) ? primary.Trim().ToLowerInvariant() : NormalizeOrNull(fallback);

    private static string? NormalizeOrNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToLowerInvariant();

    private static string Normalize(string? value) => (value ?? string.Empty).Trim().ToUpperInvariant();
}

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

    public IReadOnlyList<string>? Genres { get; init; }

    public IReadOnlyList<string>? Tags { get; init; }
}
