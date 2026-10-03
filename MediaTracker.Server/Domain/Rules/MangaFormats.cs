namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Collapses the per-source manga origin signals into the four buckets the UI shows. The sources
/// disagree on purpose-free wording, so the mapping lives here instead of in each provider: AniList
/// files OEL manga under JP (which would read as plain "manga") while MangaDex reports the original
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

    public static Enums.MangaFormat? ToEnum(string? format) =>
        NormalizeOrNull(format) switch
        {
            Manga => Enums.MangaFormat.Manga,
            Manhwa => Enums.MangaFormat.Manhwa,
            Manhua => Enums.MangaFormat.Manhua,
            Oel => Enums.MangaFormat.Oel,
            _ => null,
        };

    public static string ToStorageValue(Enums.MangaFormat format) => format switch
    {
        Enums.MangaFormat.Manhwa => Manhwa,
        Enums.MangaFormat.Manhua => Manhua,
        Enums.MangaFormat.Oel => Oel,
        _ => Manga,
    };

    private static string? FirstNonEmpty(string? primary, string? fallback) =>
        !string.IsNullOrWhiteSpace(primary) ? primary.Trim().ToLowerInvariant() : NormalizeOrNull(fallback);

    private static string? NormalizeOrNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToLowerInvariant();

    private static string Normalize(string? value) => (value ?? string.Empty).Trim().ToUpperInvariant();
}
