using System.Net;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;

/// <summary>
/// Динамический <see cref="IWebProxy"/> для SocketsHttpHandler: на каждый запрос читает текущий
/// снимок <see cref="IProxySettingsService.Current"/> и решает — идти через прокси или напрямую.
/// Включение/выключение прокси для источника вступает в силу мгновенно: снимок — immutable
/// record, новая конфигурация заменяет его по ссылке, и кэшированный <see cref="WebProxy"/>
/// перестраивается только при смене снимка. Никаких рестартов и пересоздания HttpClients.
///
/// Правила маршрутизации (в порядке проверки):
/// 1. Прокси выключен → прямое соединение.
/// 2. Цель — localhost / 127.x / приватные и link-local адреса → всегда мимо прокси
///    (<see cref="ProxyAddressGuard"/>), иначе прокси стал бы сканером локальной сети.
/// 3. Клиент привязан к источнику (именованные HttpClient провайдеров) — используется его id;
///    непривязанные клиенты (обложки, импорт) резолвят источник по корневому домену цели.
/// 4. Источник есть в <c>ProxiedSources</c> → прокси, иначе прямое соединение.
/// </summary>
public sealed class DynamicSourceProxy(IProxySettingsService settings, string? boundSourceId) : IWebProxy
{
    /// <summary>Кэш «снимок → собранный WebProxy»; замена целой ссылки атомарна, разрывов нет.</summary>
    private sealed record CacheEntry(ProxySettingsSnapshot Snapshot, IWebProxy? Proxy);

    private volatile CacheEntry? _cache;

    public Uri? GetProxy(Uri destination)
    {
        // Решение принимает снимок текущих настроек; адрес отдаёт сам кэшированный WebProxy.
        var proxy = ResolveProxy(destination);
        return proxy?.GetProxy(destination);
    }

    /// <summary>SocketsHttpHandler вызывает это параллельно с GetProxy — решения обязаны совпадать.</summary>
    public bool IsBypassed(Uri host) => ResolveProxy(host) is null;

    /// <summary>
    /// Учетные данные действующего прокси (null — прокси выключен или без авторизации).
    /// Setter есть в интерфейсе, но динамические креды приходят только из снимка настроек.
    /// </summary>
    public ICredentials? Credentials
    {
        get => CacheProxy()?.Credentials;
        set { _ = value; }
    }

    private IWebProxy? CacheProxy()
    {
        var snapshot = settings.Current;
        var cached = _cache;
        if (cached is not null && cached.Snapshot == snapshot)
        {
            return cached.Proxy;
        }

        var entry = new CacheEntry(snapshot, snapshot.BuildWebProxy());
        _cache = entry;
        return entry.Proxy;
    }

    private IWebProxy? ResolveProxy(Uri destination)
    {
        var snapshot = settings.Current;
        if (!snapshot.Enabled || snapshot.ProxyUri is null)
        {
            return null;
        }

        if (ProxyAddressGuard.IsLocalOrInternal(destination))
        {
            return null;
        }

        var sourceId = settings.ResolveSourceId(destination, boundSourceId);
        if (sourceId is null || !snapshot.ProxiedSources.Contains(sourceId))
        {
            return null;
        }

        return CacheProxy();
    }
}
