using System.Collections.Frozen;

namespace MediaTracker.Server.Features.External.SearchExternal;

/// <summary>The type filter the search box offers. "all" fans out across every supported type.</summary>
public static class SearchTypes
{
    public const string All = "all";
    public const string Game = "game";
    public const string Movie = "movie";
    public const string TvShow = "tvshow";
    public const string Anime = "anime";
    public const string Manga = "manga";
    public const string Book = "book";

    public static readonly FrozenSet<string> Supported = new[]
    {
        All,
        Game,
        Movie,
        TvShow,
        Anime,
        Manga,
        Book,
    }.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

    public static string Normalize(string? type) =>
        string.IsNullOrWhiteSpace(type) ? All : type.Trim();

    public static bool IsSupported(string type) => Supported.Contains(type);
}

/// <summary>
/// Canonical string constants for external media types to avoid stringly-typed typos
/// and ensure consistent discriminator mapping.
/// </summary>
public static class MediaType
{
    public const string Game = SearchTypes.Game;
    public const string Movie = SearchTypes.Movie;
    public const string TvShow = SearchTypes.TvShow;
    public const string Anime = SearchTypes.Anime;
    public const string Manga = SearchTypes.Manga;
    public const string Book = SearchTypes.Book;
}
