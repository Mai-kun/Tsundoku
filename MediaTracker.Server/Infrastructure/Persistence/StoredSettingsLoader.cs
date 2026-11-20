using MediaTracker.Server.Features.Settings.ProxySettings;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Security;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Restores the API keys the user saved in the settings screen. Runs once at startup, before the app
/// serves traffic, so a stored key is in place by the time a provider reads it.
/// </summary>
public sealed class StoredSettingsLoader(
    AppDbContext db,
    IEncryptionService encryption,
    IOptions<ExternalApiOptions> options,
    IEnumerable<IMetadataProvider> providers,
    IProxySettingsService proxySettings)
{
    public async Task LoadAsync(CancellationToken ct = default)
    {
        var connection = db.Connection;
        if (connection.State != System.Data.ConnectionState.Open) await connection.OpenAsync(ct);
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='Settings';";
        var settingsTableExists = (long)(await command.ExecuteScalarAsync(ct) ?? 0) > 0;

        if (!settingsTableExists) return;

        // Import-only sources (MangaLib, Simkl's user session) live in the same Settings table
        // without a provider entry, so they are concatenated explicitly.
        var keySources = providers
            .Where(p => p.RequiresApiKey || p.OptionalApiKey)
            .Select(p => p.Id)
            .Concat(new[] { ImportOnlyKeySources.MangaLib, ImportOnlyKeySources.SimklSession })
            .DistinctBy(id => id, StringComparer.OrdinalIgnoreCase);
        foreach (var sourceId in keySources)
        {
            var value = await db.GetSettingAsync($"ApiKey_{sourceId}", ct);
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            var decrypted = encryption.Decrypt(value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.Value.SetKey(sourceId, decrypted);
            }
        }

        await LoadProxySettingsAsync(ct);
    }

    /// <summary>
    /// Восстанавливает настройки прокси в живой снимок: клиенты провайдеров и обложек читают его
    /// на каждом запросе, поэтому восстановленный при старте прокси работает без рестартов.
    /// </summary>
    private async Task LoadProxySettingsAsync(CancellationToken ct)
    {
        var blob = await ProxySettingsStorage.ReadAsync(db, ct);
        var (snapshot, _) = ProxySettingsSnapshot.Build(
            blob.Enabled,
            blob.Url,
            blob.Username,
            string.IsNullOrWhiteSpace(blob.PasswordEncrypted)
                ? null
                : encryption.Decrypt(blob.PasswordEncrypted),
            blob.Sources);
        proxySettings.Update(snapshot);
    }
}
