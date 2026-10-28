using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>The library screen: one projected SQL read per request.</summary>
public interface IGetMediaListHandler
{
    Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(GetMediaListQuery query, CancellationToken ct);
}

public sealed class GetMediaListHandler(AppDbContext db) : IGetMediaListHandler
{
    public async Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(
        GetMediaListQuery query,
        CancellationToken ct)
    {
        var items = await db.LoadMediaItemsAsync(
            query.Type,
            query.Status,
            query.IsAnime,
            query.Search,
            query.SortBy,
            query.SortOrder,
            ct);

        var dtos = items.Select(MediaResponseMapper.ToListDto).ToList();
        return Result<IReadOnlyList<MediaListDto>>.Success(dtos);
    }
}
