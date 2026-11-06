using System.Collections.Frozen;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

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

        // Longest alias first: longer aliases must not be beaten by a shorter match from another
        // entry, and enumerating the dictionary directly gave a non-deterministic winner between
        // aliases that both appear in the input. The comparison is ordinal-ignore-case rather than a
        // lowercased haystack, which would allocate on every call.
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
            if (d.TotalCount == null || string.IsNullOrWhiteSpace(d.Studio) || MissingCastOrTrailer(d))
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
            if (d.RuntimeMinutes is not > 0 || string.IsNullOrWhiteSpace(d.Studio) || MissingCastOrTrailer(d))
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

    /// <summary>
    /// Cast and trailer only exist for shows and movies, and neither was a gap: the cascade saw the
    /// IMDb answer as complete, stopped, and never asked TMDb for the credits and the video the
    /// overview actually renders.
    /// ponytail: a title no source has a trailer for keeps every source in the cascade on each refresh.
    /// Worth a stored "asked" flag only when refresh latency starts to matter.
    /// </summary>
    private static bool MissingCastOrTrailer(ExternalMediaDto d) =>
        d.Cast is not { Count: > 0 } || string.IsNullOrWhiteSpace(d.TrailerVideoId);

    public static ExternalMediaDto Merge(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        return primary with
        {
            Chapters = primary.Chapters is > 0 ? primary.Chapters : fallback.Chapters,
            Volumes = primary.Volumes is > 0 ? primary.Volumes : fallback.Volumes,
            TotalCount = primary.TotalCount is > 0 ? primary.TotalCount : fallback.TotalCount,
            Author = FirstNonEmpty(primary.Author, fallback.Author),
            Studio = FirstNonEmpty(primary.Studio, fallback.Studio),
            // Cast and trailer come only from the sources that track them (TMDb, AniList); the IMDb
            // suggestion endpoint has neither, so the primary side was always null and the merge used
            // to drop the fallback's answer entirely. That is what left every show without actor
            // photos and without a trailer even when the cascade had already asked TMDb.
            Cast = BestCast(primary.Cast, fallback.Cast),
            Staff = primary.Staff is { Count: > 0 } ? primary.Staff : fallback.Staff,
            TrailerVideoId = FirstNonEmpty(primary.TrailerVideoId, fallback.TrailerVideoId),
            CreatorImageUrl = FirstNonEmpty(primary.CreatorImageUrl, fallback.CreatorImageUrl),
            Description = FirstNonEmpty(primary.Description, fallback.Description),
            CoverUrl = FirstNonEmpty(primary.CoverUrl, fallback.CoverUrl),
            ReleaseYear = primary.ReleaseYear ?? fallback.ReleaseYear,
            ReleaseDate = FirstNonEmpty(primary.ReleaseDate, fallback.ReleaseDate),
            EndDate = FirstNonEmpty(primary.EndDate, fallback.EndDate),
            ReleaseStatus = FirstNonEmpty(primary.ReleaseStatus, fallback.ReleaseStatus),
            RomajiTitle = FirstNonEmpty(primary.RomajiTitle, fallback.RomajiTitle),
            OriginalTitle = FirstNonEmpty(primary.OriginalTitle, fallback.OriginalTitle),
            // Alt titles are a union field: every source's synonyms join the pool, not just the
            // primary's. Without this the enrichment fan-out merged Romaji/Original but silently
            // dropped the fallback's synonyms, so the panel promised "Альт. названия" the merged
            // payload then never delivered.
            Synonyms = Union(primary.Synonyms, fallback.Synonyms),
            SteamAppId = FirstNonEmpty(primary.SteamAppId, fallback.SteamAppId),
            Platform = FirstNonEmpty(primary.Platform, fallback.Platform),
            // Runtime was silently dropped here: a source without a runtime used to overwrite the
            // runtime the first source had already supplied, so the DB ended up with 0 minutes.
            RuntimeMinutes = primary.RuntimeMinutes ?? fallback.RuntimeMinutes,
            // Union used to keep provider duplicates like "Action" + "Экшен" alive; the normalizer
            // collapses them into one canonical genre.
            Genres = GenreNormalizer.NormalizeList(
                primary.Genres is { Count: > 0 } ? primary.Genres.Concat(fallback.Genres ?? []) : fallback.Genres),
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
    private static readonly string[] GameSourceFragments = ["steam", "rawg"];
    private static readonly string[] BookSourceFragments = ["openlibrary", "ranobelib"];
    private static readonly string[] MangaSourceFragments = ["mangaupdates", "mangadex"];
    private static readonly string[] AnimeSourceFragments = ["anilist", "shikimori", "kitsu"];
    private static readonly string[] MovieSourceFragments = ["kinopoisk", "imdb"];

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
                if (lowerType is "all" or "")
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

    /// <summary>
    /// Keeps the cast list that actually has faces. Several sources report names only, and a list of
    /// names is worth less than a list with photos, so a photo-bearing answer wins even when it comes
    /// from the lower-priority source.
    /// </summary>
    private static IReadOnlyList<CastMemberDto>? BestCast(
        IReadOnlyList<CastMemberDto>? first,
        IReadOnlyList<CastMemberDto>? second)
    {
        var a = first is { Count: > 0 } ? first : null;
        var b = second is { Count: > 0 } ? second : null;
        if (a is not null && a.Any(member => !string.IsNullOrWhiteSpace(member.PhotoUrl))) return a;
        if (b is not null && b.Any(member => !string.IsNullOrWhiteSpace(member.PhotoUrl))) return b;
        return a ?? b;
    }

    /// <summary>
    /// The human-readable labels of every field <paramref name="fallback"/> brought into the merge.
    /// Two attribution rules live side by side:
    ///  - single-winner fields (status, episode/chapter counts, runtime, studio, synopsis...) are
    ///    credited only when the merge actually took the fallback's value over the primary's;
    ///  - accumulative fields (genres, alt titles, cover) carry multi-attribution: every source
    ///    that supplied data — even overlapping data — holds the label, because the stored list is
    ///    a union of what several providers returned.
    /// The "Рейтинг" label is not computed here: ratings bypass the merge and are credited by the
    /// enrichment fan-out that collects them.
    /// </summary>
    public static IReadOnlyList<string> DiffProvidedFields(
        ExternalMediaDto primary,
        ExternalMediaDto merged,
        ExternalMediaDto fallback,
        string type)
    {
        var fields = new List<string>();
        void Add(string label, bool changed)
        {
            if (changed && !fields.Contains(label)) fields.Add(label);
        }

        var episodeLabel = type is "anime" or "tvshow" ? "Серии" : "Главы";
        // The cast and staff labels follow the media type's vocabulary, same as the primary row's
        // provenance list in LinkedSourceCatalog: voice cast for anime, actors for films, characters
        // and authors/artists for manga and books.
        var castLabel = type is "anime" ? "Сэйю (каст)" : type is "manga" or "book" ? "Персонажи" : "Актёры";
        var staffLabel = type is "manga" or "book" ? "Авторы/Художники" : "Съёмочная группа";

        // --- Single-winner fields: the value recorded in the card has exactly one author. ---
        Add(episodeLabel, Num(merged.Chapters) != Num(primary.Chapters)
            || Num(merged.TotalCount) != Num(primary.TotalCount)
            || ListChanged(primary.Episodes, merged.Episodes)
            || ListChanged(primary.Seasons, merged.Seasons));
        Add("Тома", Num(merged.Volumes) != Num(primary.Volumes));
        Add("Студия", merged.Studio != primary.Studio);
        Add("Хронометраж", merged.RuntimeMinutes != primary.RuntimeMinutes);
        Add("Статус", merged.ReleaseStatus != primary.ReleaseStatus);
        Add("Даты выхода", merged.ReleaseYear != primary.ReleaseYear
            || merged.ReleaseDate != primary.ReleaseDate
            || merged.EndDate != primary.EndDate);
        Add("Автор", merged.Author != primary.Author);
        Add("Синопсис", merged.Description != primary.Description);
        Add("Трейлер", merged.TrailerVideoId != primary.TrailerVideoId);
        Add(castLabel, CastChanged(primary.Cast, merged.Cast));
        Add(staffLabel, ListChanged(primary.Staff, merged.Staff));
        Add("Теги", ListChanged(primary.Tags, merged.Tags));
        Add("Формат", merged.MangaFormat != primary.MangaFormat);
        Add("Платформа", merged.Platform != primary.Platform);

        // --- Accumulative fields: several sources can hold the same label. ---
        Add("Жанры", fallback.Genres is { Count: > 0 });
        Add("Альт. названия", AddsNewAltTitle(primary, fallback));
        Add("Обложка", !string.IsNullOrWhiteSpace(fallback.CoverUrl)
            && string.Equals(merged.CoverUrl, fallback.CoverUrl, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(primary.CoverUrl, fallback.CoverUrl, StringComparison.OrdinalIgnoreCase));

        return fields;
    }

    private static int Num(int? value) => value is > 0 ? value.Value : 0;

    /// <summary>Case-insensitive union; the primary's spellings keep their order, null when both sides are empty.</summary>
    private static IReadOnlyList<string>? Union(IReadOnlyList<string>? first, IReadOnlyList<string>? second)
    {
        if (first is not { Count: > 0 }) return second;
        if (second is not { Count: > 0 }) return first;

        var merged = new List<string>(first);
        foreach (var value in second)
        {
            if (!string.IsNullOrWhiteSpace(value)
                && !merged.Contains(value, StringComparer.OrdinalIgnoreCase))
            {
                merged.Add(value);
            }
        }

        return merged;
    }

    /// <summary>
    /// True when the fallback carries a title variant (romaji, original, synonym) that is not
    /// already known to the primary — i.e. one that will join the stored AltTitles blob. Equal
    /// spellings reported by both sources credit nobody twice.
    /// </summary>
    private static bool AddsNewAltTitle(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        var known = new[] { primary.Title, primary.OriginalTitle, primary.RomajiTitle }
            .Concat(primary.Synonyms ?? [])
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value!.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return new[] { fallback.RomajiTitle, fallback.OriginalTitle }
            .Concat(fallback.Synonyms ?? [])
            .Any(value => !string.IsNullOrWhiteSpace(value) && !known.Contains(value.Trim()));
    }

    /// <summary>First-wins fields: the fallback only matters when the primary side was empty.</summary>
    private static bool ListChanged<T>(IReadOnlyList<T>? before, IReadOnlyList<T>? after) =>
        before is not { Count: > 0 } && after is { Count: > 0 };

    /// <summary>
    /// Cast follows <see cref="BestCast"/>, so a non-empty primary list is still beaten when the
    /// fallback is the first answer with photos.
    /// </summary>
    private static bool CastChanged(IReadOnlyList<CastMemberDto>? before, IReadOnlyList<CastMemberDto>? after)
    {
        if (after is not { Count: > 0 }) return false;
        if (before is not { Count: > 0 }) return true;
        var beforeHadPhotos = before.Any(member => !string.IsNullOrWhiteSpace(member.PhotoUrl));
        var afterHasPhotos = after.Any(member => !string.IsNullOrWhiteSpace(member.PhotoUrl));
        return afterHasPhotos && !beforeHadPhotos;
    }

    private static string? FirstNonEmpty(string? first, string? second)
    {
        return !string.IsNullOrWhiteSpace(first) ? first : second;
    }
}
