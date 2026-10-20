using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaStats;

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
        try { return JsonSerializer.Deserialize<SmartListQueryDto>(json, JsonOpts); }
        catch { return null; }
    }

    public static IReadOnlyList<MediaItem> Evaluate(
        IEnumerable<MediaItem> allItems,
        SmartListQueryDto query)
    {
        IEnumerable<MediaItem> result = allItems;

        // Categories
        if (query.Categories is { Count: > 0 } cats)
        {
            result = result.Where(item => MatchesCategory(item, cats));
        }

        // Statuses
        if (query.Statuses is { Count: > 0 } statuses)
        {
            result = result.Where(item => statuses.Contains(item.Status));
        }

        // Score filters
        if (query.OnlyUnrated == true)
        {
            result = result.Where(item => item.Score is null or <= 0);
        }
        else
        {
            if (query.MinScore is { } min)
                result = result.Where(item => item.Score >= min);
            if (query.MaxScore is { } max)
                result = result.Where(item => item.Score <= max);
        }

        // External rating
        if (query.MinExternalRating is { } minExt)
            result = result.Where(item => item.ExternalRating >= minExt);

        // Genres — intersection after normalizing
        if (query.Genres is { Count: > 0 } genres)
        {
            var normalizedQuery = genres.Select(GenreNormalizer.Normalize).ToHashSet(StringComparer.OrdinalIgnoreCase);
            result = result.Where(item =>
            {
                if (string.IsNullOrWhiteSpace(item.Genres)) return false;
                var itemGenres = item.Genres.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Select(GenreNormalizer.Normalize);
                return itemGenres.Any(g => normalizedQuery.Contains(g));
            });
        }

        // Release year
        if (query.ReleaseYearFrom is { } yearFrom)
            result = result.Where(item => (item.ReleaseYear ?? item.ReleaseDate?.Year) >= yearFrom);
        if (query.ReleaseYearTo is { } yearTo)
            result = result.Where(item => (item.ReleaseYear ?? item.ReleaseDate?.Year) <= yearTo);

        // Volume limits
        if (query.MaxDurationMinutes is { } maxDur)
        {
            result = result.Where(item => item switch
            {
                Movie m => m.DurationMinutes > 0 && m.DurationMinutes <= maxDur,
                TvShow t => (t.EpisodeDurationMinutes ?? 24) <= maxDur,
                _ => true,
            });
        }
        if (query.MaxEpisodes is { } maxEp)
        {
            result = result.Where(item => item switch
            {
                TvShow t => t.TotalEpisodesCount > 0 && t.TotalEpisodesCount <= maxEp,
                _ => true,
            });
        }
        if (query.MaxPages is { } maxPg)
        {
            result = result.Where(item => item switch
            {
                Book b => b.TotalPages > 0 && b.TotalPages <= maxPg,
                _ => true,
            });
        }
        if (query.MaxChapters is { } maxCh)
        {
            result = result.Where(item => item switch
            {
                Manga mg => mg.TotalChapters is > 0 && mg.TotalChapters <= maxCh,
                _ => true,
            });
        }

        // Creator
        if (!string.IsNullOrWhiteSpace(query.CreatorContains))
        {
            var needle = query.CreatorContains.Trim();
            result = result.Where(item => ContainsCreator(item, needle));
        }

        // Sort
        bool desc = !string.Equals(query.SortOrder, "asc", StringComparison.OrdinalIgnoreCase);
        result = query.SortBy switch
        {
            "score" => desc
                ? result.OrderByDescending(item => item.Score ?? 0)
                : result.OrderBy(item => item.Score ?? 0),
            "externalRating" => desc
                ? result.OrderByDescending(item => item.ExternalRating ?? 0)
                : result.OrderBy(item => item.ExternalRating ?? 0),
            "releaseYear" => desc
                ? result.OrderByDescending(item => item.ReleaseYear ?? item.ReleaseDate?.Year ?? 0)
                : result.OrderBy(item => item.ReleaseYear ?? item.ReleaseDate?.Year ?? 0),
            "createdAt" => desc
                ? result.OrderByDescending(item => item.CreatedAt)
                : result.OrderBy(item => item.CreatedAt),
            "title" => desc
                ? result.OrderByDescending(item => item.Title, StringComparer.OrdinalIgnoreCase)
                : result.OrderBy(item => item.Title, StringComparer.OrdinalIgnoreCase),
            _ => result.OrderByDescending(item => item.CreatedAt),
        };

        // Limit
        if (query.Limit is > 0 and var limit)
            result = result.Take(limit);

        return result.ToList();
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
