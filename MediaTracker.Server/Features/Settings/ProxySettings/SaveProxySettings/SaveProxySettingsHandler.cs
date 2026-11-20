using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ProxySettings;

public sealed record SaveProxySettingsCommand(
    bool Enabled,
    string? ProxyUrl,
    string? Username,
    string? Password,
    string[] ProxiedSources);

public sealed record SaveProxySettingsResponse(
    bool Success,
    bool Enabled,
    bool HasPassword,
    string? MaskedPassword,
    string[] ProxiedSources);

public interface ISaveProxySettingsHandler
{
    Task<Result<SaveProxySettingsResponse>> HandleAsync(SaveProxySettingsCommand command, CancellationToken ct);
}

/// <summary>
/// Сохраняет настройки прокси (пароль шифротекстом в блобе настроек) и сразу накатывает свежий
/// снимок в <see cref="IProxySettingsService"/>: клиенты провайдеров и обложек подхватывают
/// конфигурацию на следующем запросе — без рестарта сервера.
/// </summary>
public sealed class SaveProxySettingsHandler(
    AppDbContext db,
    IEncryptionService encryption,
    IProxySettingsService proxySettings) : ISaveProxySettingsHandler
{
    public async Task<Result<SaveProxySettingsResponse>> HandleAsync(
        SaveProxySettingsCommand command,
        CancellationToken ct)
    {
        var blob = await ProxySettingsStorage.ReadAsync(db, ct);

        // null = пароль не трогали (в UI поле пустое показывает маску); "" = явная очистка.
        var plainPassword = command.Password is null
            ? (blob.PasswordEncrypted is null ? null : encryption.Decrypt(blob.PasswordEncrypted))
            : (command.Password.Length == 0 ? null : command.Password);

        var (snapshot, error) = ProxySettingsSnapshot.Build(
            command.Enabled, command.ProxyUrl, command.Username, plainPassword, command.ProxiedSources);
        if (error is not null)
        {
            return Result<SaveProxySettingsResponse>.Failure(Error.Validation(error));
        }

        var encryptedPassword = string.IsNullOrEmpty(plainPassword)
            ? null
            : encryption.Encrypt(plainPassword);

        await ProxySettingsStorage.WriteAsync(db, new ProxySettingsBlob(
            snapshot.ProxyUri?.ToString() ?? command.ProxyUrl?.Trim() ?? string.Empty,
            snapshot.Username ?? string.Empty,
            encryptedPassword,
            snapshot.Enabled,
            [.. snapshot.ProxiedSources]), ct);

        proxySettings.Update(snapshot);

        return Result<SaveProxySettingsResponse>.Success(new SaveProxySettingsResponse(
            true,
            snapshot.Enabled,
            encryptedPassword is not null,
            encryptedPassword is null ? null : ApiKeyMask.Mask(plainPassword!),
            [.. snapshot.ProxiedSources]));
    }
}
