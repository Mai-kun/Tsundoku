using System.Collections.Frozen;
using System.Text.Json;
using MediaTracker.Server.Data;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Services.External;

public interface ISourcePriorityService
{
    Task<IReadOnlyList<string>> GetPrioritiesAsync(string type, CancellationToken ct);
    Task<IReadOnlySet<string>> GetDisabledSourcesAsync(CancellationToken ct);
    Task SetSourceEnabledAsync(string sourceId, bool enabled, CancellationToken ct);
    void InvalidateCache();
}

public sealed class SourcePriorityService(
    IServiceScopeFactory scopeFactory,
    IMemoryCache cache,
    ILogger<SourcePriorityService> logger) : ISourcePriorityService
{
    public const string PriorityCacheKey = "settings:source_priority";
    public const string DisabledSourcesCacheKey = "settings:disabled_sources";
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    /// <summary>
    /// Derived from what each provider declares, ordered by its own priority. It was a hand-written
    /// dictionary, so a source could be fully registered and still be missing from the cascade the
    /// aggregator walks whenever it needs to fill a gap.
    /// </summary>
    public static readonly FrozenDictionary<string, string[]> DefaultPriorities =
        MetadataSourceRegistry.BuildDefaultPriorities().ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    public async Task<IReadOnlyList<string>> GetPrioritiesAsync(string type, CancellationToken ct)
    {
        // DefaultPriorities, the cached dict and the disabled set are all OrdinalIgnoreCase, so the type
        // needs no normalisation copy on what is a per-search path.
        var normalizedType = type?.Trim() ?? string.Empty;
        var defaultSources = DefaultPriorities.TryGetValue(normalizedType, out var def) ? def : [normalizedType];
        IReadOnlyList<string> basePriorities = defaultSources;

        if (cache.TryGetValue(PriorityCacheKey, out Dictionary<string, string[]>? cachedPriorities) && cachedPriorities is not null)
        {
            if (cachedPriorities.TryGetValue(normalizedType, out var cachedList) && cachedList.Length > 0)
            {
                basePriorities = MergePriorityLists(cachedList, defaultSources);
            }
        }
        else
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var setting = await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.Key == "SourcePriority", ct);
                if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
                {
                    var dict = JsonSerializer.Deserialize<Dictionary<string, string[]>>(setting.Value);
                    if (dict is not null)
                    {
                        cache.Set(PriorityCacheKey, dict, CacheDuration);
                        if (dict.TryGetValue(normalizedType, out var list) && list.Length > 0)
                        {
                            basePriorities = MergePriorityLists(list, defaultSources);
                        }
                    }
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "[SourcePriority] Failed to load source priorities from database, falling back to defaults");
            }
        }

        var disabled = await GetDisabledSourcesAsync(ct);
        if (disabled.Count == 0)
        {
            return basePriorities;
        }

        return basePriorities
            .Where(s => !disabled.Contains(MediaMerger.NormalizeSourceKey(s)) && !disabled.Contains(s))
            .ToList();
    }

    public async Task<IReadOnlySet<string>> GetDisabledSourcesAsync(CancellationToken ct)
    {
        if (cache.TryGetValue(DisabledSourcesCacheKey, out HashSet<string>? cached) && cached is not null)
        {
            return cached;
        }

        try
        {
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var setting = await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.Key == "DisabledSources", ct);
            if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
            {
                var list = JsonSerializer.Deserialize<List<string>>(setting.Value);
                if (list is not null)
                {
                    // The set below compares OrdinalIgnoreCase, so the entries keep their original casing and no
                    // per-source lowercase copy is allocated while the settings are parsed.
                    var set = new HashSet<string>(list.Select(s => s.Trim()), StringComparer.OrdinalIgnoreCase);
                    cache.Set(DisabledSourcesCacheKey, set, CacheDuration);
                    return set;
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "[SourcePriority] Failed to read disabled sources from database");
        }

        var empty = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        cache.Set(DisabledSourcesCacheKey, empty, CacheDuration);
        return empty;
    }

    public async Task SetSourceEnabledAsync(string sourceId, bool enabled, CancellationToken ct)
    {
        var normId = sourceId.Trim().ToLowerInvariant();

        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "DisabledSources", ct);

        var list = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<List<string>>(setting.Value);
                if (parsed is not null)
                {
                    foreach (var s in parsed) list.Add(s);
                }
            }
            catch { }
        }

        if (enabled)
        {
            list.Remove(normId);
            list.Remove(MediaMerger.NormalizeSourceKey(normId));
        }
        else
        {
            list.Add(normId);
        }

        var json = JsonSerializer.Serialize(list);
        if (setting is null)
        {
            setting = new AppSetting
            {
                Key = "DisabledSources",
                Value = json,
                UpdatedAt = DateTime.UtcNow
            };
            db.Settings.Add(setting);
        }
        else
        {
            setting.Value = json;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        cache.Set(DisabledSourcesCacheKey, list, CacheDuration);
        cache.Remove(PriorityCacheKey);
    }

    public void InvalidateCache()
    {
        cache.Remove(PriorityCacheKey);
        cache.Remove(DisabledSourcesCacheKey);
    }

    /// <summary>
    /// Folds the user order into the shipped defaults: unknown or duplicate sources are dropped and
    /// any default the user has not mentioned is appended, so a new provider can never be lost by
    /// an old saved list.
    /// </summary>
    public static Dictionary<string, string[]> MergeWithDefaults(Dictionary<string, string[]>? userPriority)
    {
        var result = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);

        foreach (var (type, defaultSources) in DefaultPriorities)
        {
            var userSources = userPriority is not null && userPriority.TryGetValue(type, out var stored) && stored.Length > 0
                ? stored
                : null;

            if (userSources is null)
            {
                result[type] = defaultSources;
                continue;
            }

            var merged = new List<string>();
            foreach (var source in userSources.Where(s => defaultSources.Contains(s, StringComparer.OrdinalIgnoreCase)))
            {
                if (!merged.Contains(source, StringComparer.OrdinalIgnoreCase))
                {
                    merged.Add(source);
                }
            }

            foreach (var source in defaultSources)
            {
                if (!merged.Contains(source, StringComparer.OrdinalIgnoreCase))
                {
                    merged.Add(source);
                }
            }

            result[type] = [.. merged];
        }

        return result;
    }

    private static List<string> MergePriorityLists(string[] userList, string[] defaultSources)
    {
        var merged = userList.Where(s => defaultSources.Contains(s, StringComparer.OrdinalIgnoreCase)).ToList();
        foreach (var s in defaultSources)
        {
            if (!merged.Contains(s, StringComparer.OrdinalIgnoreCase))
            {
                merged.Add(s);
            }
        }
        return merged;
    }
}
