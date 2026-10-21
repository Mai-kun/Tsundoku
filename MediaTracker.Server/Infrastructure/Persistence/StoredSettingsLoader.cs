using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;
using Microsoft.EntityFrameworkCore;
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
        foreach (var provider in providers.Where(p => p.RequiresApiKey).DistinctBy(p => p.Id))
        {
            var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == $"ApiKey_{provider.Id}", ct);
            if (setting is null || string.IsNullOrWhiteSpace(setting.Value))
            {
                continue;
            }

            var decrypted = encryption.Decrypt(setting.Value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.Value.SetKey(provider.Id, decrypted);
            }
        }
    }
}
