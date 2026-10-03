using System.Collections.Frozen;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>
/// Filters and ordering for the media list endpoint, expressed once so the handler stays thin.
/// </summary>
public static class MediaListQuery
{
    private const string Discriminator = "MediaType";

    private static readonly FrozenDictionary<string, string> TypeToDiscriminator =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["game"] = "Game",
            ["book"] = "Book",
            ["manga"] = "Manga",
            ["movie"] = "Movie",
            ["tvshow"] = "TvShow",
        }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

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
        query = default!;

        var trimmedType = type?.Trim();

        if (!string.IsNullOrEmpty(trimmedType) && !TypeToDiscriminator.ContainsKey(trimmedType))
        {
            return false;
        }

        // The season and volume aggregates the cards read only exist once the navigations are
        // loaded. Selecting the DTO inside the query instead let EF evaluate it in memory against
        // empty collections, so every card showed "0 / 0" and a blank franchise name.
        var scoped = MediaItemGraph.LoadNoTracking(db);

        if (trimmedType is { } discriminatorKey)
        {
            var discriminator = TypeToDiscriminator[discriminatorKey];
            scoped = scoped.Where(item => EF.Property<string>(item, Discriminator) == discriminator);
        }

        if (status is { } statusFilter)
        {
            scoped = scoped.Where(item => item.Status == statusFilter);
        }

        if (isAnime is { } animeFilter)
        {
            scoped = scoped.Where(item =>
                (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).IsAnime == animeFilter)
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).IsAnime == animeFilter));
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            scoped = ApplySearchTerm(scoped, search.Trim());
        }

        scoped = ApplyOrdering(scoped, sortBy, sortOrder);

        query = scoped;
        return true;
    }

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
        var trimmedSort = sortBy?.Trim();

        if (string.Equals(trimmedSort, "score", StringComparison.OrdinalIgnoreCase))
        {
            return isAscending
                ? query.OrderBy(item => item.Score == null).ThenBy(item => item.Score)
                : query.OrderBy(item => item.Score == null).ThenByDescending(item => item.Score);
        }

        if (string.Equals(trimmedSort, "title", StringComparison.OrdinalIgnoreCase))
        {
            return isAscending
                ? query.OrderBy(item => item.Title)
                : query.OrderByDescending(item => item.Title);
        }

        return isAscending
            ? query.OrderBy(item => item.CreatedAt)
            : query.OrderByDescending(item => item.CreatedAt);
    }
}
