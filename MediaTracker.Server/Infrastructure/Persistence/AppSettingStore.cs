using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Upserts rows in the key/value settings table. Every setting write in the app funnels through
/// here so the "insert or update" shape exists in exactly one place.
/// </summary>
public static class AppSettingStore
{
    public static async Task SetAsync(AppDbContext db, string key, string value, CancellationToken ct = default)
    {
        await db.SetSettingAsync(key, value, ct);
    }

    /// <summary>Reads a setting without tracking, so it never pins a stale row in the change tracker.</summary>
    public static async Task<string?> ReadAsync(AppDbContext db, string key, CancellationToken ct = default)
    {
        return await db.GetSettingAsync(key, ct);
    }
}
