using System.Collections.Frozen;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;

public interface IProxySettingsService
{
    /// <summary>Текущий снимок настроек. Заменяется атомарно при сохранении — без рестарта сервера.</summary>
    ProxySettingsSnapshot Current { get; }

    /// <summary>Накатывает свежий снимок (после сохранения настроек или загрузки при старте).</summary>
    void Update(ProxySettingsSnapshot snapshot);

    /// <summary>
    /// Сопоставляет целевой URI с ID источника: явно привязанный клиент использует свой id,
    /// остальные (обложки, импорт) — по корневому домену адресов источников из реестра.
    /// </summary>
    string? ResolveSourceId(Uri destination, string? boundSourceId);
}

/// <summary>
/// Хранит снимок настроек прокси и таблицу «корневой домен → источник». Таблица собирается один
/// раз из статического реестра <see cref="MetadataSourceRegistry"/> (BaseAddress каждого
/// провайдера) плюс явных CDN-домены обложек, которых нет в BaseAddress (SocialLib раздаёт
/// обложки с cover.imglib.info / cover.cdnlibs.org, а его API живёт на mangalib.me).
/// </summary>
public sealed class ProxySettingsService : IProxySettingsService
{
    private volatile ProxySettingsSnapshot _current = ProxySettingsSnapshot.Disabled;

    /// <summary>Корневой домен → ID источника (OrdinalIgnoreCase). Иммуtable после построения.</summary>
    private static readonly FrozenDictionary<string, string> HostToSource = BuildHostMap();

    public ProxySettingsSnapshot Current => _current;

    public void Update(ProxySettingsSnapshot snapshot) => _current = snapshot;

    public string? ResolveSourceId(Uri destination, string? boundSourceId)
    {
        if (!string.IsNullOrEmpty(boundSourceId))
        {
            return boundSourceId;
        }

        return HostToSource.TryGetValue(RootDomain(destination.Host), out var sourceId)
            ? sourceId
            : null;
    }

    /// <summary>
    /// Последние две метки хоста — маппинг «обложечный CDN → источник»: uploads.mangadex.org и
    /// api.mangadex.org это один источник, image.tmdb.org и api.themoviedb.org — другой. Все
    /// адреса проекта укладываются в схему (ccTLD-секундные домены вида co.uk в реестре нет).
    /// </summary>
    public static string RootDomain(string host)
    {
        var name = host.Trim().TrimEnd('.').ToLowerInvariant();
        var labels = name.Split('.');
        return labels.Length <= 2 ? name : string.Join('.', labels[^2..]);
    }

    private static FrozenDictionary<string, string> BuildHostMap()
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var descriptor in MetadataSourceRegistry.All)
        {
            // Офлайн-базы живут на 127.0.0.1 — ProxyAddressGuard и так не пускает их в прокси.
            if (descriptor.Id.Equals("offline", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (!Uri.TryCreate(descriptor.BaseAddress, UriKind.Absolute, out var baseUri))
            {
                continue;
            }

            var root = RootDomain(baseUri.Host);
            if (!string.IsNullOrEmpty(root))
            {
                map[root] = descriptor.Id;
            }
        }

        // CDN обложек, чей корневой домен отличается от корня API-адреса источника: SocialLib
        // раздаёт обложки через DDoS-Guard-защищённые хосты (см. ImageStorageService.
        // CreateImageRequest), а его дескриптор не объявляет BaseAddress вовсе — все адреса в
        // запросах абсолютные; обложки TMDb живут на image.tmdb.org (корень tmdb.org, тогда как
        // API — api.themoviedb.org / themoviedb.org); постеры IMDb — на m.media-amazon.com.
        map["imglib.info"] = "sociallib";
        map["cdnlibs.org"] = "sociallib";
        map["mangalib.me"] = "sociallib";
        map["tmdb.org"] = "tmdb";
        map["media-amazon.com"] = "imdb";

        return map.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
    }
}
