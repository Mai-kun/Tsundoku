using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MetadataAggregatorService(
    IServiceProvider serviceProvider,
    IMemoryCache cache)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    public static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string type, string query, CancellationToken ct)
    {
        var normalizedType = type.Trim().ToLowerInvariant();
        var normalizedQuery = query.Trim();
        var cacheKey = $"{(normalizedType.Length == 0 ? "all" : normalizedType)}:{normalizedQuery.ToLowerInvariant()}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        var results = normalizedType is "all" or ""
            ? await SearchAllAsync(normalizedQuery, ct)
            : await SearchProviderAsync(normalizedType, normalizedQuery, ct);

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderAsync(string type, string query, CancellationToken ct)
    {
        var provider = serviceProvider.GetRequiredKeyedService<IMetadataProvider>(type);
        return await provider.SearchAsync(query, ct);
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchAllAsync(string query, CancellationToken ct)
    {
        var tasks = AllTypes.Select(type => SearchProviderSafeAsync(type, query, ct));
        var groups = await Task.WhenAll(tasks);

        return groups.SelectMany(group => group).ToList();
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderSafeAsync(string type, string query, CancellationToken ct)
    {
        try
        {
            return await SearchProviderAsync(type, query, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return [];
        }
    }
}
