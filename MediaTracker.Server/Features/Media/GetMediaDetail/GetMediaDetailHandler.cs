using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetMediaDetail;

public sealed record GetMediaDetailQuery(Guid Id);

/// <summary>
/// The detail screen. Read-only by contract: no change tracker and no write. The first volume a manga
/// detail view needs is seeded when the item is created and lazily on the first volume mutation, so a
/// GET never has to insert a row to be able to render.
/// </summary>
public interface IGetMediaDetailHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(GetMediaDetailQuery query, CancellationToken ct);
}

public sealed class GetMediaDetailHandler(AppDbContext db) : IGetMediaDetailHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(GetMediaDetailQuery query, CancellationToken ct)
    {
        var item = await MediaItemGraph
            .LoadNoTracking(db)
            .SingleOrDefaultAsync(media => media.Id == query.Id, ct);

        return item is null
            ? Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{query.Id}' was not found."))
            : Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}

/// <summary>
/// The includes every write path shares. Two collection includes in one query multiply into a
/// cartesian product, so the query is split into one round trip per collection.
/// </summary>
public static class MediaItemGraph
{
    public static IQueryable<MediaItem> LoadTracked(AppDbContext db) =>
        db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .AsSplitQuery();

    public static IQueryable<MediaItem> LoadNoTracking(AppDbContext db) =>
        LoadTracked(db).AsNoTracking();
}
