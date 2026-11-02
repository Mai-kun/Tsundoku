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
