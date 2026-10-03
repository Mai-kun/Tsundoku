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
                db.MediaItems,
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

        var rows = await built.ToListAsync(ct);
        var items = new List<MediaListDto>(rows.Count);

        foreach (var row in rows)
        {
            items.Add(MediaListProjection.WithCoverVersion(row.Item, row.UpdatedAt));
        }

        return Result<IReadOnlyList<MediaListDto>>.Success(items);
    }
}
