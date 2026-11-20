using System.Threading;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Settings.NavigationCategories;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>The library screen: one projected SQL read per request.</summary>
public interface IGetMediaListHandler
{
    /// <summary>Returns the mapped DTO list directly; retrieving it from memory takes 0.001ms.</summary>
    Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(GetMediaListQuery query, CancellationToken ct);

    /// <summary>
    /// Same list as <see cref="HandleAsync"/> plus the true total matching count
    /// (the DB row count behind the limit/offset window), used for X-Total-Count.
    /// </summary>
    Task<(IReadOnlyList<MediaListDto> Items, int TotalCount)> HandleWithCountAsync(
        GetMediaListQuery query,
        CancellationToken ct);
}

public static class MediaListCache
{
    private static int _version = 1;
    public static int Version => Volatile.Read(ref _version);
    public static void Invalidate() => Interlocked.Increment(ref _version);
    public static string BuildKey(GetMediaListQuery q) =>
        $"media:list:v{Version}:{q.Type}:{q.Status}:{q.IsAnime}:{q.SubId}:{q.Search}:{q.SortBy}:{q.SortOrder}:{q.Limit}:{q.Offset}";
}

/// <summary>
/// Caches the mapped DTO list in memory; retrieving the pre-mapped list takes 0.001ms.
/// </summary>
public sealed class GetMediaListHandler(
    AppDbContext db,
    IMemoryCache? cache = null,
    INavigationCategoriesService? navigationCategories = null) : IGetMediaListHandler
{
    // Тесты конструируют хендлер напрямую без сервиса категорий: тогда взаимного
    // исключения просто нет — поведение совпадает с дот-фичной версией.
    private IReadOnlyList<PromotedSubcategory> ActiveForParent(string parentType) =>
        navigationCategories?.ActiveForParent(parentType) ?? [];

    private PromotedSubcategory? FindSubcategory(string id) => navigationCategories?.Find(id);

    public async Task<Result<IReadOnlyList<MediaListDto>>> HandleAsync(
        GetMediaListQuery query,
        CancellationToken ct)
    {
        var resolved = ResolveSubcategory(query);
        var key = MediaListCache.BuildKey(query);
        if (cache is not null && cache.TryGetValue(key, out IReadOnlyList<MediaListDto>? cached) && cached is not null)
        {
            return Result<IReadOnlyList<MediaListDto>>.Success(cached);
        }

        var items = await db.LoadMediaItemsAsync(
            resolved.Type,
            query.Status,
            query.IsAnime,
            query.Search,
            query.SortBy,
            query.SortOrder,
            ct,
            query.Limit,
            query.Offset,
            resolved.Include,
            resolved.Exclude);

        var dtos = items.Select(MediaResponseMapper.ToListDto).ToList();
        if (cache is not null)
        {
            cache.Set(key, dtos, TimeSpan.FromMinutes(10));
        }
        return Result<IReadOnlyList<MediaListDto>>.Success(dtos);
    }

    public async Task<(IReadOnlyList<MediaListDto> Items, int TotalCount)> HandleWithCountAsync(
        GetMediaListQuery query,
        CancellationToken ct)
    {
        var resolved = ResolveSubcategory(query);
        var items = await HandleAsync(query, ct);

        var countKey = $"{MediaListCache.BuildKey(query)}:total";
        if (cache is not null
            && cache.TryGetValue(countKey, out int? cachedTotal)
            && cachedTotal is not null)
        {
            return (items.Value ?? [], cachedTotal.Value);
        }

        var total = await db.GetMediaTotalCountAsync(
            resolved.Type,
            query.Status,
            query.IsAnime,
            query.Search,
            ct,
            resolved.Include,
            resolved.Exclude);
        if (cache is not null)
        {
            cache.Set(countKey, total, TimeSpan.FromMinutes(10));
        }
        return (items.Value ?? [], total);
    }

    /// <summary>
    /// Разбирает запрошенную категорию в SQL-фильтры: запрошена вынесенная подкатегория —
    /// запрос идёт по её родительскому типу с match-условием; запрошен родитель — из него
    /// исключаются все активные подкатегории этого типа (взаимное исключение с «Аниме»
    /// не пересекается: у Book/Manga флага аниме нет).
    /// </summary>
    private (string? Type, PromotedSubcategory? Include, IReadOnlyList<PromotedSubcategory>? Exclude)
        ResolveSubcategory(GetMediaListQuery query)
    {
        if (string.IsNullOrWhiteSpace(query.SubId))
        {
            if (string.IsNullOrEmpty(query.Type))
            {
                return (query.Type, null, null);
            }

            var exclude = ActiveForParent(query.Type);
            return (query.Type, null, exclude.Count > 0 ? exclude : null);
        }

        var sub = FindSubcategory(query.SubId)
            ?? throw new InvalidOperationException($"Unknown navigation subcategory '{query.SubId}'.");
        return (sub.ParentType, sub, null);
    }
}
