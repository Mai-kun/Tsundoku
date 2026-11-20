using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ProxySettings;

/// <summary>Пароль отдаётся только маскированным: прочитать сохранённый пароль через API нельзя.</summary>
public sealed record ProxySettingsDto(
    bool Enabled,
    string ProxyUrl,
    string? Username,
    bool HasPassword,
    string? MaskedPassword,
    string[] ProxiedSources);

public interface IGetProxySettingsHandler
{
    Task<Result<ProxySettingsDto>> HandleAsync(CancellationToken ct);
}

public sealed class GetProxySettingsHandler(
    AppDbContext db,
    IEncryptionService encryption) : IGetProxySettingsHandler
{
    public async Task<Result<ProxySettingsDto>> HandleAsync(CancellationToken ct)
    {
        var blob = await ProxySettingsStorage.ReadAsync(db, ct);
        var hasPassword = !string.IsNullOrWhiteSpace(blob.PasswordEncrypted);
        var masked = hasPassword
            ? ApiKeyMask.Mask(encryption.Decrypt(blob.PasswordEncrypted!) ?? string.Empty)
            : null;

        return Result<ProxySettingsDto>.Success(new ProxySettingsDto(
            blob.Enabled,
            blob.Url,
            string.IsNullOrWhiteSpace(blob.Username) ? null : blob.Username,
            hasPassword,
            masked,
            blob.Sources));
    }
}
