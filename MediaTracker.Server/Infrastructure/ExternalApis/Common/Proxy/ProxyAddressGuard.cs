using System.Net;
using System.Net.Sockets;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;

/// <summary>
/// Единая проверка адресов для всего, что ходит наружу: локальные, приватные и link-local
/// адреса никогда не отправляются через внешний прокси (и не fetch'аются image-proxy
/// эндпоинтом). Прокси-провайдер получает только публичные интернет-хосты — иначе прокси
/// превращается в инструмент сканирования локальной сети.
/// </summary>
public static class ProxyAddressGuard
{
    private static readonly string[] InternalSuffixes =
    [
        ".localhost",
        ".local",
        ".lan",
        ".internal",
        ".home.arpa",
    ];

    /// <summary>
    /// Нормализованное имя хоста — публичный интернет-хост? DNS-имена считаются публичными:
    /// фактические адреса резолвит сам HttpClient (это одно-пользовательское десктоп-приложение,
    /// текстовая проверка адресов — достаточная SSRF-защита).
    /// </summary>
    public static bool IsPublicHost(string? host)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        var name = host.Trim().TrimEnd('.').ToLowerInvariant();
        if (name.Length == 0)
        {
            return false;
        }

        if (name is "localhost" or "localhost.localdomain")
        {
            return false;
        }

        foreach (var suffix in InternalSuffixes)
        {
            if (name.EndsWith(suffix, StringComparison.Ordinal))
            {
                return false;
            }
        }

        return !IPAddress.TryParse(name, out var ip) || IsPublicAddress(ip);
    }

    /// <summary>Полный URI назначения проксируется? Локальные цели — всегда мимо прокси.</summary>
    public static bool IsLocalOrInternal(Uri destination) => !IsPublicHost(destination.Host);

    private static bool IsPublicAddress(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = address.GetAddressBytes();
            return !(b[0] is 0 or 10 or 127
                || b[0] is 169 && b[1] is 254
                || b[0] is 172 && b[1] is >= 16 and <= 31
                || b[0] is 192 && b[1] is 168
                || b[0] is 100 && b[1] is >= 64 and <= 127);
        }

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            return !(address.IsIPv6LinkLocal
                || address.IsIPv6SiteLocal
                || address.IsIPv6UniqueLocal
                || IPAddress.IPv6Loopback.Equals(address));
        }

        return false;
    }
}
