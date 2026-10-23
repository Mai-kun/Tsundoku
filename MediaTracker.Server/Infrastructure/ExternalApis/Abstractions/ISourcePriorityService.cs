namespace MediaTracker.Server.Infrastructure.ExternalApis;

public interface ISourcePriorityService
{
    ValueTask<IReadOnlyList<string>> GetPrioritiesAsync(string type, CancellationToken ct);
    Task<IReadOnlySet<string>> GetDisabledSourcesAsync(CancellationToken ct);
    Task SetSourceEnabledAsync(string sourceId, bool enabled, CancellationToken ct);
    void InvalidateCache();

    /// <summary>
    /// Bumps on every priority/enablement change, so dependent caches (the aggregator search cache)
    /// can fold it into their keys and go stale the moment the settings change — without any
    /// manual eviction across cache keys.
    /// </summary>
    int Version { get; }
}
