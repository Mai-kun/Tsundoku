using MediaTracker.Server.Data;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Services.Media;

/// <summary>Filters and ordering for the media list endpoint, expressed once so the handler stays thin.</summary>
public static class MediaListQuery
{
    private const string Discriminator = "MediaType";

    private static readonly IReadOnlyDictionary<string, string> TypeToDiscriminator =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["game"] = "Game",
            ["book"] = "Book",
            ["manga"] = "Manga",
            ["movie"] = "Movie",
            ["tvshow"] = "TvShow",
        };

    /// <summary>Returns false when the requested type is unknown — the caller answers with an empty list.</summary>
    public static bool TryBuild(
        AppDbContext db,
        string? type,
        MediaStatus? status,
        bool? isAnime,
        string? search,
        string? sortBy,
        string? sortOrder,
        out IQueryable<MediaItem> query)
    {
        var normalizedType = type?.Trim().ToLowerInvariant();
        query = default!;

        if (!string.IsNullOrWhiteSpace(normalizedType) && !TypeToDiscriminator.ContainsKey(normalizedType))
        {
            return false;
        }

        query = db.MediaItems
            .AsNoTracking()
            .Include(media => media.Franchise);

        // Only load the child collections the requested slice can actually render.
        if (IncludesSeasons(normalizedType))
        {
            query = query.Include(media => ((TvShow)media).Seasons);
        }

        if (IncludesVolumes(normalizedType))
        {
            query = query.Include(media => ((Manga)media).Volumes);
        }

        if (!string.IsNullOrWhiteSpace(normalizedType))
        {
            var discriminator = TypeToDiscriminator[normalizedType];
            query = query.Where(item => EF.Property<string>(item, Discriminator) == discriminator);
        }

        if (status is { } statusFilter)
        {
            query = query.Where(item => item.Status == statusFilter);
        }

        if (isAnime is { } animeFilter)
        {
            query = query.Where(item =>
                (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).IsAnime == animeFilter)
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).IsAnime == animeFilter));
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = ApplySearchTerm(query, search.Trim());
        }

        query = ApplyOrdering(query, sortBy, sortOrder);
        return true;
    }

    private static bool IncludesSeasons(string? normalizedType) =>
        string.IsNullOrWhiteSpace(normalizedType) || normalizedType is "tvshow";

    private static bool IncludesVolumes(string? normalizedType) =>
        string.IsNullOrWhiteSpace(normalizedType) || normalizedType is "manga";

    private static IQueryable<MediaItem> ApplySearchTerm(IQueryable<MediaItem> query, string term)
    {
        var pattern = $"%{term}%";
        return query.Where(item =>
            EF.Functions.Like(item.Title, pattern)
            || (item.Franchise != null && EF.Functions.Like(item.Franchise.Name, pattern))
            || (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).RomajiTitle != null && EF.Functions.Like(((Movie)item).RomajiTitle, pattern))
            || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).RomajiTitle != null && EF.Functions.Like(((TvShow)item).RomajiTitle, pattern)));
    }

    private static IQueryable<MediaItem> ApplyOrdering(IQueryable<MediaItem> query, string? sortBy, string? sortOrder)
    {
        var isAscending = string.Equals(sortOrder, "asc", StringComparison.OrdinalIgnoreCase);

        return sortBy?.Trim().ToLowerInvariant() switch
        {
            "score" => isAscending
                ? query.OrderBy(item => item.Score == null).ThenBy(item => item.Score)
                : query.OrderBy(item => item.Score == null).ThenByDescending(item => item.Score),
            "title" => isAscending
                ? query.OrderBy(item => item.Title)
                : query.OrderByDescending(item => item.Title),
            _ => isAscending
                ? query.OrderBy(item => item.CreatedAt)
                : query.OrderByDescending(item => item.CreatedAt),
        };
    }
}
