using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.Settings.SaveSourceKey;

public sealed record SaveSourceKeyCommand(string SourceId, string? ApiKey);

public sealed record SaveSourceKeyResponse(bool Success, bool HasKey, string? MaskedKey);

public interface ISaveSourceKeyHandler
{
    Task<Result<SaveSourceKeyResponse>> HandleAsync(SaveSourceKeyCommand command, CancellationToken ct);
}

/// <summary>Stores a provider key encrypted and pushes it into the live options so it applies at once.</summary>
public sealed class SaveSourceKeyHandler(
    AppDbContext db,
    IEncryptionService encryption,
    IOptions<ExternalApiOptions> options,
    IEnumerable<IMetadataProvider> providers) : ISaveSourceKeyHandler
{
    public async Task<Result<SaveSourceKeyResponse>> HandleAsync(
        SaveSourceKeyCommand command,
        CancellationToken ct)
    {
        var normalizedId = command.SourceId.Trim().ToLowerInvariant();
        var provider = providers.FirstOrDefault(p =>
            p.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase));

        if (provider?.RequiresApiKey is false)
        {
            return Result<SaveSourceKeyResponse>.Failure(
                Error.Validation($"Source '{command.SourceId}' does not require an API key."));
        }

        var key = command.ApiKey?.Trim() ?? string.Empty;
        var encrypted = string.IsNullOrEmpty(key) ? string.Empty : encryption.Encrypt(key);

        await AppSettingStore.SetAsync(db, $"ApiKey_{normalizedId}", encrypted, ct);

        options.Value.SetKey(normalizedId, key);

        return Result<SaveSourceKeyResponse>.Success(
            new SaveSourceKeyResponse(true, !string.IsNullOrEmpty(key), ApiKeyMask.Mask(key)));
    }
}
