using System.Collections.Frozen;

namespace MediaTracker.Server.Services.External;

public static class MediaMerger
{
    private static readonly FrozenDictionary<string, string> CanonicalNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["mal"] = "MyAnimeList",
        ["jikan"] = "MyAnimeList",
        ["myanimelist"] = "MyAnimeList",
        ["anilist"] = "AniList",
        ["mangaupdates"] = "MangaUpdates",
        ["mangadex"] = "MangaDex",
        ["tmdb"] = "TMDB",
        ["rawg"] = "RAWG",
        ["openlibrary"] = "OpenLibrary",
        ["kitsu"] = "Kitsu",
        ["shikimori"] = "Shikimori",
        ["googlebooks"] = "Google Books",
        ["google"] = "Google Books",
        ["steam"] = "Steam",
        ["imdb"] = "IMDb",
        ["simkl"] = "Simkl",
        ["thetvdb"] = "TheTVDB",
        ["tvdb"] = "TheTVDB",
        ["kinopoisk"] = "Kinopoisk",
        ["igdb"] = "IGDB"
    }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>Same mapping, ordered longest-alias-first so substring matching is deterministic.</summary>
    private static readonly (string Alias, string Canonical)[] CanonicalNamesByLength =
        [.. CanonicalNames.OrderByDescending(entry => entry.Key.Length).Select(entry => (entry.Key, entry.Value))];

    /// <summary>
    /// Maps any source spelling the UI may send (canonical name, provider id, free text) onto the
    /// canonical id used as the settings key. Data-driven so a new provider is one table entry.
    /// </summary>
    private static readonly FrozenDictionary<string, string> SourceKeyAliases =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["mal"] = "jikan",
            ["myanimelist"] = "jikan",
            ["jikan"] = "jikan",
            ["anilist"] = "anilist",
            ["shikimori"] = "shikimori",
            ["kitsu"] = "kitsu",
            ["mangaupdates"] = "mangaupdates",
            ["mangadex"] = "mangadex",
            ["googlebooks"] = "googlebooks",
            ["google"] = "googlebooks",
            ["steam"] = "steam",
            ["rawg"] = "rawg",
            ["igdb"] = "igdb",
            ["imdb"] = "imdb",
            ["simkl"] = "simkl",
            ["thetvdb"] = "thetvdb",
            ["tvdb"] = "thetvdb",
            ["kinopoisk"] = "kinopoisk",
            ["tmdb"] = "tmdb",
            ["movie database"] = "tmdb",
            ["openlibrary"] = "openlibrary",
        }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>Alias table ordered longest-first so substring matching resolves deterministically.</summary>
    private static readonly (string Alias, string Canonical)[] SourceKeyAliasesByLength =
        [.. SourceKeyAliases.OrderByDescending(entry => entry.Key.Length).Select(entry => (entry.Key, entry.Value))];

    public static string GetCanonicalSourceName(string source)
    {
        if (string.IsNullOrWhiteSpace(source))
        {
            return string.Empty;
        }

        var trimmed = source.Trim();
        if (CanonicalNames.TryGetValue(trimmed, out var exactMatch))
        {
            return exactMatch;
        }

        // Longest alias first: "thetvdb" must not be matched by the shorter "tvdb" of another entry,
        // and enumerating the dictionary directly gave a non-deterministic winner between aliases
        // that both appear in the input (e.g. "tvdb" is a substring of "thetvdb").
        var lower = trimmed.ToLowerInvariant();
        foreach (var (key, canonical) in CanonicalNamesByLength)
        {
            if (lower.Contains(key))
            {
                return canonical;
            }
        }

        return source;
    }
    public static bool HasMissingMetadata(ExternalMediaDto d, string type)
    {
        if (type == "manga")
        {
            if (d.Chapters == null || d.Volumes == null || string.IsNullOrWhiteSpace(d.Author))
            {
                return true;
            }
        }
        else if (type is "anime" or "tvshow")
        {
            if (d.TotalCount == null || string.IsNullOrWhiteSpace(d.Studio))
            {
                return true;
            }
        }
        else if (type == "book")
        {
            if (d.TotalCount == null || string.IsNullOrWhiteSpace(d.Author))
            {
                return true;
            }
        }
        else if (type == "movie")
        {
            // Movies had no branch at all, so runtime and studio never counted as "missing" and the
            // cascade stopped at the first source instead of asking the remaining ones.
            if (d.RuntimeMinutes is not > 0 || string.IsNullOrWhiteSpace(d.Studio))
            {
                return true;
            }
        }

        // Release status is deliberately NOT checked here. No source reports it for most titles, so
        // making it a gap would mean querying every source on every request forever. MediaItemFactory
        // derives it from the dates instead, which is where the real answer lives.
        return string.IsNullOrWhiteSpace(d.Description)
            || d.ReleaseYear == null
            || string.IsNullOrWhiteSpace(d.ReleaseDate);
    }

    public static ExternalMediaDto Merge(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        return primary with
        {
            Chapters = primary.Chapters ?? fallback.Chapters,
            Volumes = primary.Volumes ?? fallback.Volumes,
            TotalCount = primary.TotalCount ?? fallback.TotalCount ?? fallback.Chapters ?? fallback.Volumes,
            Author = FirstNonEmpty(primary.Author, fallback.Author),
            Studio = FirstNonEmpty(primary.Studio, fallback.Studio),
            Description = FirstNonEmpty(primary.Description, fallback.Description),
            CoverUrl = FirstNonEmpty(primary.CoverUrl, fallback.CoverUrl),
            ReleaseYear = primary.ReleaseYear ?? fallback.ReleaseYear,
            ReleaseDate = FirstNonEmpty(primary.ReleaseDate, fallback.ReleaseDate),
            EndDate = FirstNonEmpty(primary.EndDate, fallback.EndDate),
            ReleaseStatus = FirstNonEmpty(primary.ReleaseStatus, fallback.ReleaseStatus),
            RomajiTitle = FirstNonEmpty(primary.RomajiTitle, fallback.RomajiTitle),
            OriginalTitle = FirstNonEmpty(primary.OriginalTitle, fallback.OriginalTitle),
            Platform = FirstNonEmpty(primary.Platform, fallback.Platform),
            // Runtime was silently dropped here: a source without a runtime used to overwrite the
            // runtime the first source had already supplied, so the DB ended up with 0 minutes.
            RuntimeMinutes = primary.RuntimeMinutes ?? fallback.RuntimeMinutes,
            Genres = primary.Genres is { Count: > 0 } ? primary.Genres : fallback.Genres,
            Tags = primary.Tags is { Count: > 0 } ? primary.Tags : fallback.Tags,
            // OEL can only come from the second source, so the plain "first wins" rule is wrong here.
            MangaFormat = MangaFormats.Pick(primary.MangaFormat, fallback.MangaFormat),
            Episodes = primary.Episodes is { Count: > 0 } ? primary.Episodes : fallback.Episodes
        };
    }

    public static string NormalizeMediaType(string type, string? source = null)
    {
        var lowerType = type?.Trim().ToLowerInvariant() ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(source))
        {
            var lowerSource = source.Trim().ToLowerInvariant();
            if (lowerSource.Contains("steam") || lowerSource.Contains("igdb"))
            {
                return "game";
            }
            if (lowerSource.Contains("google"))
            {
                return "book";
            }
            if (lowerSource.Contains("mangaupdates") || lowerSource.Contains("mangadex"))
            {
                return "manga";
            }
            if (lowerSource.Contains("anilist") || lowerSource.Contains("jikan") || lowerSource.Contains("mal") || lowerSource.Contains("shikimori") || lowerSource.Contains("kitsu"))
            {
                if (lowerType is "tvshow" or "movie" or "all" or "")
                {
                    return "anime";
                }
            }
            if (lowerSource.Contains("kinopoisk") || lowerSource.Contains("imdb") || lowerSource.Contains("tvdb") || lowerSource.Contains("thetvdb"))
            {
                if (lowerType is "anime" or "all" or "")
                {
                    return "movie";
                }
            }
        }
        return lowerType;
    }

    public static string NormalizeSourceKey(string source)
    {
        var lower = source.Trim().ToLowerInvariant();

        // Longest alias first keeps the original cascade semantics ("myanimelist" before "mal"
        // would not matter, but "movie database" must beat a bare "tmdb" prefix match).
        foreach (var (alias, canonical) in SourceKeyAliasesByLength)
        {
            if (lower.Contains(alias))
            {
                return canonical;
            }
        }

        return lower;
    }

    private static string? FirstNonEmpty(string? first, string? second)
    {
        return !string.IsNullOrWhiteSpace(first) ? first : second;
    }
}
