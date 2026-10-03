using System.Collections.Frozen;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>
/// Filters, ordering and the DTO projection for the media list endpoint, expressed once so the
/// handler stays thin. The projection keeps the read in a single SQL statement: no TPH entity graph
/// is materialized and the season/volume collections are reduced to aggregates by the database.
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
        IQueryable<MediaItem> source,
        string? type,
        MediaStatus? status,
        bool? isAnime,
        string? search,
        string? sortBy,
        string? sortOrder,
        out IQueryable<MediaListRow> query)
    {
        query = default!;

        var trimmedType = type?.Trim();

        if (!string.IsNullOrEmpty(trimmedType) && !TypeToDiscriminator.ContainsKey(trimmedType))
        {
            return false;
        }

        var scoped = source.AsNoTracking();

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

        query = MediaListProjection.ProjectRows(scoped);
        return true;
    }

    /// <summary>
    /// One list row: the projected DTO plus the raw update timestamp the cover cache-buster is
    /// derived from. Ticks is not SQL-translatable, so the version string is stamped in memory.
    /// </summary>
    public sealed record MediaListRow(MediaListDto Item, DateTime UpdatedAt);

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
