using System.Collections.Frozen;
using MediaTracker.Server.Domain.Rules;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public static class MediaMerger
{
    /// <summary>
    /// Both alias tables are built from what the providers declare, so a new source brings its own
    /// spelling aliases along. They were two hand-written dictionaries that had to be edited
    /// alongside the registration list, which is how a new source ended up resolvable by id but
    /// unresolvable by any name a user would type.
    /// </summary>
    private static readonly FrozenDictionary<string, string> CanonicalNames =
        MetadataSourceRegistry.BuildCanonicalNames().ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>Same mapping, ordered longest-alias-first so substring matching is deterministic.</summary>
    private static readonly (string Alias, string Canonical)[] CanonicalNamesByLength =
        [.. CanonicalNames.OrderByDescending(entry => entry.Key.Length).Select(entry => (entry.Key, entry.Value))];

    /// <summary>
    /// Maps any source spelling the UI may send (canonical name, provider id, free text) onto the
    /// canonical id used as the settings key.
    /// </summary>
    private static readonly FrozenDictionary<string, string> SourceKeyAliases =
        MetadataSourceRegistry.BuildSourceKeyAliases().ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Alias table ordered longest-first. The aliases and ids providers declare are mixed case
    /// ("MyAnimeList", "TheTVDB"), so matching them has to be case-insensitive; doing that with the
    /// comparison overload avoids allocating a lowercase copy of the input on every call.
    /// </summary>
    private static readonly (string Alias, string Canonical)[] SourceKeyAliasesByLength =
    [
        .. SourceKeyAliases
            .OrderByDescending(entry => entry.Key.Length)
            .Select(entry => (entry.Key, entry.Value))
    ];

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
        // that both appear in the input (e.g. "tvdb" is a substring of "thetvdb"). The comparison is
        // ordinal-ignore-case rather than a lowercased haystack, which would allocate on every call.
        foreach (var (key, canonical) in CanonicalNamesByLength)
        {
            if (trimmed.Contains(key, StringComparison.OrdinalIgnoreCase))
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
            Chapters = BestCount(primary.Chapters, fallback.Chapters),
            Volumes = BestCount(primary.Volumes, fallback.Volumes),
            TotalCount = BestCount(
                primary.TotalCount,
                fallback.TotalCount,
                primary.Chapters,
                fallback.Chapters,
                fallback.Volumes),
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
            SteamAppId = FirstNonEmpty(primary.SteamAppId, fallback.SteamAppId),
            Platform = FirstNonEmpty(primary.Platform, fallback.Platform),
            // Runtime was silently dropped here: a source without a runtime used to overwrite the
            // runtime the first source had already supplied, so the DB ended up with 0 minutes.
            RuntimeMinutes = primary.RuntimeMinutes ?? fallback.RuntimeMinutes,
            Genres = primary.Genres?.Union(fallback.Genres ?? [], StringComparer.OrdinalIgnoreCase).Distinct(StringComparer.OrdinalIgnoreCase).ToList() ?? fallback.Genres ?? [],
            Tags = primary.Tags is { Count: > 0 } ? primary.Tags : fallback.Tags,
            // OEL can only come from the second source, so the plain "first wins" rule is wrong here.
            MangaFormat = MangaFormats.Pick(primary.MangaFormat, fallback.MangaFormat),
            Episodes = primary.Episodes is { Count: > 0 } ? primary.Episodes : fallback.Episodes,
            // A source that knows the real season split (Kinopoisk) must not be overwritten by one
            // that only reports a flat episode count, or the split is lost again on merge.
            Seasons = primary.Seasons is { Count: > 0 } ? primary.Seasons : fallback.Seasons,
        };
    }

    /// <summary>
    /// Source-id fragments that pin a media type regardless of what the caller asked for. Static
    /// arrays rather than params: this runs once per source per enrichment, so no call may allocate.
    /// </summary>
    private static readonly string[] GameSourceFragments = ["steam", "igdb"];
    private static readonly string[] BookSourceFragments = ["google"];
    private static readonly string[] MangaSourceFragments = ["mangaupdates", "mangadex"];
    private static readonly string[] AnimeSourceFragments = ["anilist", "jikan", "mal", "shikimori", "kitsu"];
    private static readonly string[] MovieSourceFragments = ["kinopoisk", "imdb", "tvdb", "thetvdb"];

    public static string NormalizeMediaType(string type, string? source = null)
    {
        var lowerType = type?.Trim().ToLowerInvariant() ?? string.Empty;
        var trimmedSource = source?.Trim();
        if (!string.IsNullOrWhiteSpace(trimmedSource))
        {
            // The fragments compare with an explicit StringComparison instead of a lowercased copy of
            // the source: this runs once per source per enrichment and the haystack is never stored.
            if (MentionsAny(trimmedSource, GameSourceFragments))
            {
                return "game";
            }
            if (MentionsAny(trimmedSource, BookSourceFragments))
            {
                return "book";
            }
            if (MentionsAny(trimmedSource, MangaSourceFragments))
            {
                return "manga";
            }
            if (MentionsAny(trimmedSource, AnimeSourceFragments))
            {
                if (lowerType is "tvshow" or "movie" or "all" or "")
                {
                    return "anime";
                }
            }
            if (MentionsAny(trimmedSource, MovieSourceFragments))
            {
                if (lowerType is "anime" or "all" or "")
                {
                    return "movie";
                }
            }
        }
        return lowerType;
    }

    private static bool MentionsAny(string haystack, string[] fragments)
    {
        foreach (var fragment in fragments)
        {
            if (haystack.Contains(fragment, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    public static string NormalizeSourceKey(string source)
    {
        var trimmed = source.Trim();

        // Longest alias first keeps the original cascade semantics ("myanimelist" before "mal"
        // would not matter, but "movie database" must beat a bare "tmdb" prefix match).
        foreach (var (alias, canonical) in SourceKeyAliasesByLength)
        {
            if (trimmed.Contains(alias, StringComparison.OrdinalIgnoreCase))
            {
                return canonical;
            }
        }

        return trimmed.ToLowerInvariant();
    }

    private static string? FirstNonEmpty(string? first, string? second)
    {
        return !string.IsNullOrWhiteSpace(first) ? first : second;
    }

    /// <summary>
    /// Picks the count to keep when two sources disagree.
    ///
    /// Coalescing on nullability alone was the bug behind "Гл. 0 / —" on an ongoing series: an
    /// ongoing source reports either no count at all or only the latest chapter, and neither was
    /// allowed to lose the final total another source already knew (386 for Berserk). A count that
    /// is missing or zero is not an answer, so the largest real one wins and the result is null only
    /// when nobody knows.
    /// </summary>
    private static int? BestCount(params int?[] candidates)
    {
        int? best = null;
        foreach (var candidate in candidates)
        {
            if (candidate is not > 0)
            {
                continue;
            }

            best = best is null || candidate > best ? candidate : best;
        }

        return best;
    }
}
