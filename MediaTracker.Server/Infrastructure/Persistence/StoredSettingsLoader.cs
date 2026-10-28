using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// Restores the API keys the user saved in the settings screen. Runs once at startup, before the app
/// serves traffic, so a stored key is in place by the time a provider reads it.
/// </summary>
public sealed class StoredSettingsLoader(
    AppDbContext db,
    IEncryptionService encryption,
    IOptions<ExternalApiOptions> options,
    IEnumerable<IMetadataProvider> providers)
{
    public async Task LoadAsync(CancellationToken ct = default)
    {
        var connection = db.Connection;
        if (connection.State != System.Data.ConnectionState.Open) await connection.OpenAsync(ct);
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='Settings';";
        var settingsTableExists = (long)(await command.ExecuteScalarAsync(ct) ?? 0) > 0;

        if (!settingsTableExists) return;

        foreach (var provider in providers.Where(p => p.RequiresApiKey || p.OptionalApiKey).DistinctBy(p => p.Id))
        {
            var value = await db.GetSettingAsync($"ApiKey_{provider.Id}", ct);
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            var decrypted = encryption.Decrypt(value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.Value.SetKey(provider.Id, decrypted);
            }
        }
    }
}
