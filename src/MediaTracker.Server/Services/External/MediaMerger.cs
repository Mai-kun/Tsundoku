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

        var lower = trimmed.ToLowerInvariant();
        foreach (var (key, canonical) in CanonicalNames)
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

        return string.IsNullOrWhiteSpace(d.Description) || d.ReleaseYear == null;
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
        if (lower.Contains("mal") || lower.Contains("myanimelist") || lower.Contains("jikan"))
        {
            return "jikan";
        }
        if (lower.Contains("shikimori"))
        {
            return "shikimori";
        }
        if (lower.Contains("mangaupdates"))
        {
            return "mangaupdates";
        }
        if (lower.Contains("mangadex"))
        {
            return "mangadex";
        }
        if (lower.Contains("anilist"))
        {
            return "anilist";
        }
        if (lower.Contains("kitsu"))
        {
            return "kitsu";
        }
        if (lower.Contains("google"))
        {
            return "googlebooks";
        }
        if (lower.Contains("steam"))
        {
            return "steam";
        }
        if (lower.Contains("imdb"))
        {
            return "imdb";
        }
        if (lower.Contains("simkl"))
        {
            return "simkl";
        }
        if (lower.Contains("tvdb") || lower.Contains("thetvdb"))
        {
            return "thetvdb";
        }
        if (lower.Contains("kinopoisk"))
        {
            return "kinopoisk";
        }
        if (lower.Contains("igdb"))
        {
            return "igdb";
        }
        if (lower.Contains("tmdb") || lower.Contains("movie database"))
        {
            return "tmdb";
        }
        if (lower.Contains("rawg"))
        {
            return "rawg";
        }
        if (lower.Contains("openlibrary"))
        {
            return "openlibrary";
        }
        return lower;
    }

    private static string? FirstNonEmpty(string? first, string? second)
    {
        return !string.IsNullOrWhiteSpace(first) ? first : second;
    }
}
