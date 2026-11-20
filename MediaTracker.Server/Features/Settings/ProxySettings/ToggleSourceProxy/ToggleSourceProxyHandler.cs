using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ProxySettings;

public sealed record ToggleSourceProxyCommand(string SourceId, bool Proxied);

/// <summary>Тело запроса: id источника приходит из маршрута.</summary>
public sealed record ToggleSourceProxyRequest(bool Proxied);

public sealed record ToggleSourceProxyResponse(
    bool Success,
    bool IsProxied,
    string[] ProxiedSources);

public interface IToggleSourceProxyHandler
{
    Task<Result<ToggleSourceProxyResponse>> HandleAsync(ToggleSourceProxyCommand command, CancellationToken ct);
}

/// <summary>
/// Переключает конкретный источник на прокси одним кликом с карточки источника. Блокирует
/// включение, пока прокси не настроен (нет адреса при выключенном мастере) — иначе тумблер
/// создавал бы иллюзию работы. Снимок обновляется сразу: следующий же запрос источника
/// уходит через прокси, рестарт не нужен.
/// </summary>
public sealed class ToggleSourceProxyHandler(
    AppDbContext db,
    IEncryptionService encryption,
    IProxySettingsService proxySettings) : IToggleSourceProxyHandler
{
    public async Task<Result<ToggleSourceProxyResponse>> HandleAsync(
        ToggleSourceProxyCommand command,
        CancellationToken ct)
    {
        var normalizedId = command.SourceId.Trim().ToLowerInvariant();
        var knownId = MetadataSourceRegistry.All
            .Select(descriptor => descriptor.Id)
            .FirstOrDefault(id => id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase));
        if (knownId is null || knownId.Equals("offline", StringComparison.OrdinalIgnoreCase))
        {
            return Result<ToggleSourceProxyResponse>.Failure(
                Error.NotFound($"Source '{command.SourceId}' cannot be routed through a proxy."));
        }

        var blob = await ProxySettingsStorage.ReadAsync(db, ct);

        var sources = blob.Sources.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (command.Proxied)
        {
            // Включить источник через прокси можно только когда прокси настроен: адрес есть
            // (или мастер включён) — иначе клиенты пойдут напрямую и тумблер будет врать.
            if (string.IsNullOrWhiteSpace(blob.Url))
            {
                return Result<ToggleSourceProxyResponse>.Failure(
                    Error.Validation("Configure the proxy URL before routing sources through it."));
            }

            sources.Add(knownId);
        }
        else
        {
            sources.Remove(knownId);
        }

        var plainPassword = string.IsNullOrWhiteSpace(blob.PasswordEncrypted)
            ? null
            : encryption.Decrypt(blob.PasswordEncrypted);

        var (snapshot, error) = ProxySettingsSnapshot.Build(
            blob.Enabled, blob.Url, blob.Username, plainPassword, sources);
        if (error is not null)
        {
            return Result<ToggleSourceProxyResponse>.Failure(Error.Validation(error));
        }

        await ProxySettingsStorage.WriteAsync(db, blob with { Sources = [.. sources] }, ct);
        proxySettings.Update(snapshot);

        return Result<ToggleSourceProxyResponse>.Success(new ToggleSourceProxyResponse(
            true,
            sources.Contains(knownId),
            [.. snapshot.ProxiedSources]));
    }
}
