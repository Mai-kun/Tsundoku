using System.Net;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;

/// <summary>
/// Неизменяемый снимок действующих настроек прокси. Объекты живут только для чтения и заменяются
/// целиком при сохранении настроек, поэтому <see cref="DynamicSourceProxy"/> может без блокировок
/// подхватывать свежую конфигурацию: сравнение по ссылке решает, нужно ли перестроить
/// <see cref="WebProxy"/>. Никаких обращений к БД на горячем пути.
/// </summary>
/// <param name="Enabled">Общий мастер-рубильник проксирования.</param>
/// <param name="ProxyUri">Адрес прокси (http://, https://, socks5:// или socks5h://).</param>
/// <param name="Username">Логин прокси, если задан.</param>
/// <param name="Password">Расшифрованный пароль прокси; живёт только в памяти процесса.</param>
/// <param name="ProxiedSources">ID источников, ходящих через прокси (OrdinalIgnoreCase).</param>
public sealed record ProxySettingsSnapshot(
    bool Enabled,
    Uri? ProxyUri,
    string? Username,
    string? Password,
    IReadOnlySet<string> ProxiedSources)
{
    // Пустое множество объявлено ДО Disabled: инициализаторы статических полей выполняются
    // по порядку, и Disabled захватывает ссылку на уже созданное множество.
    private static readonly IReadOnlySet<string> EmptySources =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    /// <summary>Прокси выключен: все клиенты идут напрямую.</summary>
    public static ProxySettingsSnapshot Disabled { get; } =
        new(false, null, null, null, EmptySources);

    public static readonly string[] AllowedSchemes = ["http", "https", "socks5", "socks5h"];

    /// <summary>
    /// Строит снимок из пользовательского ввода. Возвращает ошибку, если адрес задан, но не
    /// парсится или указывает на запрещённую схему — порт/хост прокси проверяются до записи в БД.
    /// </summary>
    public static (ProxySettingsSnapshot Snapshot, string? Error) Build(
        bool enabled,
        string? proxyUrl,
        string? username,
        string? password,
        IEnumerable<string> proxiedSources)
    {
        var sources = proxiedSources
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        Uri? proxyUri = null;
        if (enabled || !string.IsNullOrWhiteSpace(proxyUrl))
        {
            var trimmed = proxyUrl?.Trim() ?? string.Empty;
            if (trimmed.Length == 0)
            {
                if (enabled)
                {
                    return (Disabled, "Proxy URL is required when the proxy is enabled.");
                }
            }
            else if (!Uri.TryCreate(trimmed, UriKind.Absolute, out proxyUri)
                || !AllowedSchemes.Contains(proxyUri.Scheme))
            {
                return (Disabled,
                    $"Proxy URL must be an absolute http://, https://, socks5:// or socks5h:// address, got '{trimmed}'.");
            }
        }

        return (new ProxySettingsSnapshot(
            enabled && proxyUri is not null,
            proxyUri,
            NullIfEmpty(username),
            NullIfEmpty(password),
            sources), null);
    }

    /// <summary>WebProxy для SocketsHttpHandler; socks5 передаётся как есть — .NET 6+ держит SOCKS нативно.</summary>
    public IWebProxy? BuildWebProxy()
    {
        if (!Enabled || ProxyUri is null)
        {
            return null;
        }

        var proxy = new WebProxy(ProxyUri);
        if (!string.IsNullOrEmpty(Username))
        {
            proxy.Credentials = new NetworkCredential(Username, Password ?? string.Empty);
        }

        return proxy;
    }

    private static string? NullIfEmpty(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
