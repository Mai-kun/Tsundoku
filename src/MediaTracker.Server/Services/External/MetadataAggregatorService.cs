using System.Text.Json;
using MediaTracker.Server.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MetadataAggregatorService(
    IServiceProvider serviceProvider,
    IMemoryCache cache)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    public static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    public static readonly Dictionary<string, string[]> DefaultSourcePriority = new()
    {
        ["anime"] = ["anilist", "jikan"],
        ["manga"] = ["anilist", "mangaupdates", "jikan"],
        ["movie"] = ["tmdb"],
        ["tvshow"] = ["tmdb"],
        ["game"] = ["rawg"],
        ["book"] = ["openlibrary"]
    };

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
            : await SearchProviderWithFallbackAsync(normalizedType, normalizedQuery, ct);

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string type, string externalId, string title, CancellationToken ct, string? source = null)
    {
        var normalizedType = type.Trim().ToLowerInvariant();

        if (!string.IsNullOrWhiteSpace(source))
        {
            var normalizedSource = NormalizeSourceKey(source);
            var directProvider = serviceProvider.GetKeyedService<IMetadataProvider>($"{normalizedType}:{normalizedSource}")
                                 ?? serviceProvider.GetKeyedService<IMetadataProvider>(normalizedSource);

            if (directProvider is not null)
            {
                try
                {
                    var details = await directProvider.GetDetailsAsync(externalId, title, ct);
                    if (details is not null)
                    {
                        return details;
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    throw;
                }
                catch
                {
                    // Fall back to priority list
                }
            }
        }

        var prioritySources = await GetSourcePriorityForTypeAsync(normalizedType, ct);
        foreach (var src in prioritySources)
        {
            var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{normalizedType}:{src}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(src)
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(normalizedType);

            if (provider is null)
            {
                continue;
            }

            try
            {
                var details = await provider.GetDetailsAsync(externalId, title, ct);
                if (details is not null)
                {
                    return details;
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                // Try next
            }
        }

        return null;
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderWithFallbackAsync(string type, string query, CancellationToken ct)
    {
        var prioritySources = await GetSourcePriorityForTypeAsync(type, ct);

        foreach (var source in prioritySources)
        {
            ct.ThrowIfCancellationRequested();

            var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{type}:{source}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(source)
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(type);

            if (provider is null)
            {
                continue;
            }

            try
            {
                var results = await provider.SearchAsync(query, ct);
                if (results.Count > 0)
                {
                    return results;
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                // Fall back to next source
            }
        }

        return [];
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
            return await SearchProviderWithFallbackAsync(type, query, ct);
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

    private async Task<IReadOnlyList<string>> GetSourcePriorityForTypeAsync(string type, CancellationToken ct)
    {
        try
        {
            using var scope = serviceProvider.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "SourcePriority", ct);
            if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
            {
                var dict = JsonSerializer.Deserialize<Dictionary<string, string[]>>(setting.Value);
                if (dict != null && dict.TryGetValue(type, out var list) && list.Length > 0)
                {
                    return list;
                }
            }
        }
        catch
        {
            // fallback
        }

        return DefaultSourcePriority.TryGetValue(type, out var defaultList)
            ? defaultList
            : [type];
    }

    private static string NormalizeSourceKey(string source)
    {
        var lower = source.Trim().ToLowerInvariant();
        if (lower.Contains("mal") || lower.Contains("myanimelist") || lower.Contains("jikan"))
            return "jikan";
        if (lower.Contains("mangaupdates"))
            return "mangaupdates";
        if (lower.Contains("anilist"))
            return "anilist";
        if (lower.Contains("tmdb") || lower.Contains("movie database"))
            return "tmdb";
        if (lower.Contains("rawg"))
            return "rawg";
        if (lower.Contains("openlibrary"))
            return "openlibrary";
        return lower;
    }
}
