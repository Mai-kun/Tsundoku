using MediaTracker.Server.Data;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Services.Settings;

/// <summary>
/// Upserts rows in the key/value settings table. Every setting write in the app funnels through
/// here so the "insert or update" shape exists in exactly one place.
/// </summary>
public static class AppSettingStore
{
    public static async Task SetAsync(AppDbContext db, string key, string value, CancellationToken ct = default)
    {
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == key, ct);

        if (setting is null)
        {
            db.Settings.Add(new AppSetting
            {
                Key = key,
                Value = value,
                UpdatedAt = DateTime.UtcNow
            });
        }
        else
        {
            setting.Value = value;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
    }

    /// <summary>Reads a setting without tracking, so it never pins a stale row in the change tracker.</summary>
    public static async Task<string?> ReadAsync(AppDbContext db, string key, CancellationToken ct = default)
    {
        var setting = await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.Key == key, ct);
        return string.IsNullOrWhiteSpace(setting?.Value) ? null : setting.Value;
    }
}
