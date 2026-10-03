using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetMediaList;

public sealed record GetMediaListQuery(
    string? Type = null,
    MediaStatus? Status = null,
    bool? IsAnime = null,
    string? Search = null,
    string? SortBy = "createdAt",
    string? SortOrder = "desc");

/// <summary>The library screen: one projected SQL read per request, no TPH graph materialized.</summary>
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
        if (!MediaListQuery.TryBuild(
                db,
                query.Type,
                query.Status,
                query.IsAnime,
                query.Search,
                query.SortBy,
                query.SortOrder,
                out var built))
        {
            return Result<IReadOnlyList<MediaListDto>>.Success([]);
        }

        // The same mapper the detail screen uses, so a card and the page it opens can never report
        // different totals. It runs in memory on purpose: the season/volume collections have to be
        // loaded for those aggregates to mean anything.
        var loaded = await built.ToListAsync(ct);
        var items = new List<MediaListDto>(loaded.Count);

        foreach (var item in loaded)
        {
            items.Add(MediaResponseMapper.ToListDto(item));
        }

        return Result<IReadOnlyList<MediaListDto>>.Success(items);
    }
}
