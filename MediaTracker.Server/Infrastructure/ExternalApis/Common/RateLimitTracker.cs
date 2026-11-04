using System.Collections.Concurrent;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed record ApiRateLimitStatus(
    string Provider,
    int Remaining,
    int Limit,
    int ResetSecondsRemaining,
    DateTime UpdatedAt);

public sealed class RateLimitTracker
{
    private readonly ConcurrentDictionary<string, (int Remaining, int Limit, int ResetSeconds, DateTime UpdatedAt, string ProviderName)> _limits =
        new(StringComparer.OrdinalIgnoreCase);

    public void Update(string providerKey, string providerName, int remaining, int limit, int resetSecondsRemaining)
    {
        if (limit <= 0 && _limits.TryGetValue(providerKey, out var prev) && prev.Limit > 0)
        {
            limit = prev.Limit;
        }

        if (limit > 0 && remaining > limit)
        {
            limit = remaining;
        }

        _limits[providerKey] = (remaining, limit, resetSecondsRemaining, DateTime.UtcNow, providerName);
    }

    public ApiRateLimitStatus? GetStatus(string providerKey)
    {
        if (_limits.TryGetValue(providerKey, out var tuple))
        {
            var elapsed = (int)(DateTime.UtcNow - tuple.UpdatedAt).TotalSeconds;
            var currentReset = Math.Max(0, tuple.ResetSeconds - elapsed);
            return new ApiRateLimitStatus(
                tuple.ProviderName,
                tuple.Remaining,
                tuple.Limit,
                currentReset,
                tuple.UpdatedAt);
        }
        return null;
    }

    public void RecordRateLimitExceeded(string providerKey, string providerName, int fallbackResetSeconds = 60)
    {
        _limits.AddOrUpdate(
            providerKey,
            _ => (0, 90, fallbackResetSeconds, DateTime.UtcNow, providerName),
            (_, prev) => (0, prev.Limit > 0 ? prev.Limit : 90, fallbackResetSeconds, DateTime.UtcNow, providerName));
    }

    public IReadOnlyList<ApiRateLimitStatus> GetAll()
    {
        var now = DateTime.UtcNow;
        var result = new List<ApiRateLimitStatus>(_limits.Count);

        foreach (var (_, (remaining, limit, resetSeconds, updatedAt, providerName)) in _limits)
        {
            var elapsed = (int)(now - updatedAt).TotalSeconds;
            var currentReset = Math.Max(0, resetSeconds - elapsed);
            result.Add(new ApiRateLimitStatus(
                providerName,
                remaining,
                limit,
                currentReset,
                updatedAt));
        }

        result.Sort((a, b) => string.Compare(a.Provider, b.Provider, StringComparison.OrdinalIgnoreCase));
        return result;
    }
}
