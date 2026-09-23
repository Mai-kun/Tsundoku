using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MetadataAggregatorService(
    IServiceProvider serviceProvider,
    IMemoryCache cache)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string type, string query, CancellationToken ct)
    {
        var normalizedType = type.Trim().ToLowerInvariant();
        var normalizedQuery = query.Trim();
        var cacheKey = $"{normalizedType}:{normalizedQuery.ToLowerInvariant()}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        var provider = serviceProvider.GetRequiredKeyedService<IMetadataProvider>(normalizedType);
        var results = await provider.SearchAsync(normalizedQuery, ct);

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }
}
