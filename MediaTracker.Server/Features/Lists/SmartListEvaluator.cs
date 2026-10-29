using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaStats;

using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.Lists;

public sealed record SmartListQueryDto
{
    public List<string>? Categories { get; init; }
    public List<MediaStatus>? Statuses { get; init; }
    public int? MinScore { get; init; }
    public int? MaxScore { get; init; }
    public bool? OnlyUnrated { get; init; }
    public double? MinExternalRating { get; init; }
    public List<string>? Genres { get; init; }
    public int? ReleaseYearFrom { get; init; }
    public int? ReleaseYearTo { get; init; }
    public int? MaxDurationMinutes { get; init; }
    public int? MaxEpisodes { get; init; }
    public int? MaxPages { get; init; }
    public int? MaxChapters { get; init; }
    public string? CreatorContains { get; init; }
    public string? SortBy { get; init; }
    public string? SortOrder { get; init; }
    public int? Limit { get; init; }
}

public static class SmartListEvaluator
{
    private static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);

    public static SmartListQueryDto? ParseQuery(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize(json, AppJsonSerializerContext.Default.SmartListQueryDto); }
        catch { return null; }
    }

    public static IReadOnlyList<MediaItem> Evaluate(
        IEnumerable<MediaItem> allItems,
        SmartListQueryDto query)
    {
        // Single allocation: one list built in one pass, then sorted in place.
        var filtered = new List<MediaItem>(allItems is ICollection<MediaItem> col ? col.Count : 128);

        // Pre-compute target genres once (normalized, OrdinalIgnoreCase lookup).
        HashSet<string>? targetGenres = null;
        if (query.Genres is { Count: > 0 } genres)
        {
            targetGenres = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var g in genres)
            {
                targetGenres.Add(GenreNormalizer.Normalize(g));
            }
        }

        // Caches normalized item-genre strings within this call so repeated genres are
        // normalized once instead of once-per-item (Normalize allocates a StringBuilder + string).
        Dictionary<string, string>? genreNormCache = null;

        // Resolve sort direction and key selector up front so the loop is branch-free.
        bool desc = !string.Equals(query.SortOrder, "asc", StringComparison.OrdinalIgnoreCase);

        bool onlyUnrated = query.OnlyUnrated == true;
        int? minScore = query.MinScore;
        int? maxScore = query.MaxScore;
        double? minExt = query.MinExternalRating;
        int? yearFrom = query.ReleaseYearFrom;
        int? yearTo = query.ReleaseYearTo;
        int? maxDur = query.MaxDurationMinutes;
        int? maxEp = query.MaxEpisodes;
        int? maxPg = query.MaxPages;
        int? maxCh = query.MaxChapters;
        string? creatorNeedle = string.IsNullOrWhiteSpace(query.CreatorContains) ? null : query.CreatorContains.Trim();

        foreach (var item in allItems)
        {
            // Categories
            if (query.Categories is { Count: > 0 } cats && !MatchesCategory(item, cats)) continue;

            // Statuses
            if (query.Statuses is { Count: > 0 } statuses && !statuses.Contains(item.Status)) continue;

            // Score
            if (onlyUnrated)
            {
                if (item.Score is not null and > 0) continue;
            }
            else
            {
                if (minScore is { } min && (item.Score is null || item.Score < min)) continue;
                if (maxScore is { } max && (item.Score is null || item.Score > max)) continue;
            }

            // External rating
            if (minExt is { } minExtVal && (item.ExternalRating is null || item.ExternalRating < minExtVal)) continue;

            // Genres — intersection against pre-normalized target set. Inline scan over ','/';'
            // segments avoids ExtractGenres' per-part string[] and Trim allocations; normalization
            // results are cached so each unique genre string is normalized once.
            if (targetGenres is not null)
            {
                var itemGenres = item.Genres;
                if (string.IsNullOrWhiteSpace(itemGenres)) continue;
                bool genreMatch = false;
                int start = 0;
                for (int i = 0; i <= itemGenres.Length; i++)
                {
                    if (i == itemGenres.Length || itemGenres[i] is ',' or ';')
                    {
                        var segment = itemGenres.AsSpan(start, i - start).Trim();
                        if (!segment.IsEmpty)
                        {
                            string normalized;
                            if (genreNormCache is null) genreNormCache = new();
                            var raw = segment.ToString();
                            if (!genreNormCache.TryGetValue(raw, out string? cached))
                            {
                                normalized = GenreNormalizer.Normalize(raw);
                                genreNormCache[raw] = normalized;
                            }
                            else
                            {
                                normalized = cached ?? string.Empty;
                            }
                            if (targetGenres.Contains(normalized))
                            {
                                genreMatch = true;
                                break;
                            }
                        }
                        start = i + 1;
                    }
                }
                if (!genreMatch) continue;
            }

            // Release year
            var itemYear = item.ReleaseYear ?? item.ReleaseDate?.Year;
            if (yearFrom is { } yf && itemYear < yf) continue;
            if (yearTo is { } yt && itemYear > yt) continue;

            // Volume limits
            if (maxDur is { } md)
            {
                bool durOk = item switch
                {
                    Movie m => m.DurationMinutes > 0 && m.DurationMinutes <= md,
                    TvShow t => (t.EpisodeDurationMinutes ?? 24) <= md,
                    _ => true,
                };
                if (!durOk) continue;
            }
            if (maxEp is { } me)
            {
                bool epOk = item switch
                {
                    TvShow t => t.TotalEpisodesCount > 0 && t.TotalEpisodesCount <= me,
                    _ => true,
                };
                if (!epOk) continue;
            }
            if (maxPg is { } mp)
            {
                bool pgOk = item switch
                {
                    Book b => b.TotalPages > 0 && b.TotalPages <= mp,
                    _ => true,
                };
                if (!pgOk) continue;
            }
            if (maxCh is { } mc)
            {
                bool chOk = item switch
                {
                    Manga mg => mg.TotalChapters is > 0 && mg.TotalChapters <= mc,
                    _ => true,
                };
                if (!chOk) continue;
            }

            // Creator
            if (creatorNeedle is not null && !ContainsCreator(item, creatorNeedle)) continue;

            filtered.Add(item);
        }

        // In-place sort — no OrderedEnumerable or delegate allocations.
        Sort(filtered, query.SortBy, desc);

        // Limit
        if (query.Limit is > 0 and var limit && limit < filtered.Count)
        {
            filtered.RemoveRange(limit, filtered.Count - limit);
        }

        return filtered;
    }

    private static void Sort(List<MediaItem> filtered, string? sortBy, bool desc)
    {
        // Null-safe comparison: nulls sort as 0, matching the original OrderBy(... ?? 0) semantics.
        int dir = desc ? -1 : 1;
        int cmp(MediaItem x, MediaItem y) => sortBy switch
        {
            "score" => dir * (x.Score ?? 0).CompareTo(y.Score ?? 0),
            "externalRating" => dir * (x.ExternalRating ?? 0).CompareTo(y.ExternalRating ?? 0),
            "releaseYear" => dir * (x.ReleaseYear ?? x.ReleaseDate?.Year ?? 0).CompareTo(y.ReleaseYear ?? y.ReleaseDate?.Year ?? 0),
            "createdAt" => dir * x.CreatedAt.CompareTo(y.CreatedAt),
            "title" => dir * string.Compare(x.Title ?? string.Empty, y.Title ?? string.Empty, StringComparison.OrdinalIgnoreCase),
            _ => dir * x.CreatedAt.CompareTo(y.CreatedAt),
        };
        filtered.Sort(cmp);
    }

    private static bool MatchesCategory(MediaItem item, List<string> cats)
    {
        foreach (var cat in cats)
        {
            var matches = cat.ToLowerInvariant() switch
            {
                "anime" => item is TvShow { IsAnime: true } or Movie { IsAnime: true },
                "tvshow" => item is TvShow { IsAnime: false },
                "movie" => item is Movie { IsAnime: false },
                "game" => item is VideoGame,
                "manga" => item is Manga,
                "book" => item is Book,
                _ => false,
            };
            if (matches) return true;
        }
        return false;
    }

    private static bool ContainsCreator(MediaItem item, string needle)
    {
        return item switch
        {
            Movie m => Contains(m.Studio, needle) || Contains(m.Director, needle),
            TvShow t => Contains(t.Studio, needle),
            VideoGame g => Contains(g.Studio, needle),
            Book b => Contains(b.Author, needle),
            Manga mg => Contains(mg.Author, needle),
            _ => false,
        };

        static bool Contains(string? field, string needle) =>
            field is not null && field.Contains(needle, StringComparison.OrdinalIgnoreCase);
    }

}
