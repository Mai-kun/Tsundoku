using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ProxySettings;

/// <summary>
/// Пользовательские настройки прокси как единый JSON-блоб в таблице Settings (ключ
/// <see cref="SettingsKey"/>). Пароль хранится шифротекстом <see cref="IEncryptionService"/>;
/// в расшифрованном виде он существует только в снимке <see cref="ProxySettingsSnapshot"/>.
/// Блоб регистрируется в <see cref="AppJsonSerializerContext"/> — рефлексии нет.
/// </summary>
public sealed record ProxySettingsBlob(
    string Url,
    string Username,
    string? PasswordEncrypted,
    bool Enabled,
    string[] Sources);

public static class ProxySettingsStorage
{
    public const string SettingsKey = "App_ProxySettings";

    /// <summary>Значения по умолчанию: прокси выключен, список источников пуст.</summary>
    public static ProxySettingsBlob Default { get; } =
        new(string.Empty, string.Empty, null, false, []);

    public static ProxySettingsBlob Read(AppDbContext db, CancellationToken ct) =>
        JsonSettings.TryDeserialize<ProxySettingsBlob>(
            AppSettingStore.ReadAsync(db, SettingsKey, ct).GetAwaiter().GetResult())
        ?? Default;

    public static async Task<ProxySettingsBlob> ReadAsync(AppDbContext db, CancellationToken ct)
    {
        var json = await AppSettingStore.ReadAsync(db, SettingsKey, ct);
        return JsonSettings.TryDeserialize<ProxySettingsBlob>(json) ?? Default;
    }

    public static Task WriteAsync(AppDbContext db, ProxySettingsBlob blob, CancellationToken ct) =>
        AppSettingStore.SetAsync(db, SettingsKey, JsonSettings.Serialize(blob), ct);
}
