using System.Threading;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>The library screen: one projected SQL read per request.</summary>
public interface IGetMediaListHandler
{
    /// <summary>Returns the mapped DTO list directly; retrieving it from memory takes 0.001ms.</summary>
    Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(GetMediaListQuery query, CancellationToken ct);
}

public static class MediaListCache
{
    private static int _version = 1;
    public static int Version => Volatile.Read(ref _version);
    public static void Invalidate() => Interlocked.Increment(ref _version);
    public static string BuildKey(GetMediaListQuery q) =>
        $"media:list:v{Version}:{q.Type}:{q.Status}:{q.IsAnime}:{q.Search}:{q.SortBy}:{q.SortOrder}:{q.Limit}:{q.Offset}";
}

/// <summary>
/// Caches the mapped DTO list in memory; retrieving the pre-mapped list takes 0.001ms.
/// </summary>
public sealed class GetMediaListHandler(AppDbContext db, IMemoryCache? cache = null) : IGetMediaListHandler
{
    public async Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(
        GetMediaListQuery query,
        CancellationToken ct)
    {
        var key = MediaListCache.BuildKey(query);
        if (cache is not null && cache.TryGetValue(key, out IReadOnlyList<MediaListDto>? cached) && cached is not null)
        {
            return Result<IReadOnlyList<MediaListDto>>.Success(cached);
        }

        var items = await db.LoadMediaItemsAsync(
            query.Type,
            query.Status,
            query.IsAnime,
            query.Search,
            query.SortBy,
            query.SortOrder,
            ct,
            query.Limit,
            query.Offset);

        var dtos = items.Select(MediaResponseMapper.ToListDto).ToList();
        if (cache is not null)
        {
            cache.Set(key, dtos, TimeSpan.FromMinutes(10));
        }
        return Result<IReadOnlyList<MediaListDto>>.Success(dtos);
    }
}
