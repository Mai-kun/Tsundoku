using System.Net;
using System.Net.Sockets;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Features.External.ProxyExternalImage;

/// <summary>
/// Streams an external cover image through the server. Several sources (the SocialLib family on
/// cover.imglib.info behind DDoS-Guard, MangaDex's bot-walled uploads CDN) answer a plain browser
/// &lt;img&gt; request with 403 — the same URLs download fine server-side once the browser-ish
/// headers from <see cref="ImageStorageService.CreateImageRequest"/> are attached. Every external
/// search preview routes through this endpoint, so successful downloads also land in the disk
/// cache (<see cref="SearchCacheService"/>, three-day TTL): a repeat preview is served straight
/// from the local file with zero requests to the CDN.
/// </summary>
public static class ProxyExternalImageEndpoint
{
    /// <summary>
    /// Hard ceiling for one proxied image; the stream wrapper aborts anything larger, so a
    /// misbehaving host cannot push an unbounded body into memory or the disk cache.
    /// </summary>
    private const long MaxImageSizeBytes = 10 * 1024 * 1024;

    /// <summary>
    /// Browser-side freshness hint, aligned with the server-side TTL: after three days the
    /// browser asks the server again, which either serves a fresh cache file or re-downloads.
    /// </summary>
    private const int CacheControlMaxAgeSeconds = 72 * 60 * 60;

    /// <summary>
    /// Only public internet hosts are fetchable. The endpoint fetches whatever URL the search
    /// results reference, so the guard moved from a host whitelist to the SSRF minimum: no
    /// loopback, private, link-local or otherwise internal targets — the proxy must never be
    /// turned into a port-scanner for the local network. DNS-name hosts are resolved by the
    /// HttpClient itself; this is a single-user desktop app talking to image CDNs, so a textual
    /// address check is the proportionate guard.
    /// </summary>
    internal static bool IsAllowedRemoteHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host)) return false;

        var name = host.Trim().TrimEnd('.').ToLowerInvariant();
        if (name.Length == 0) return false;
        if (name is "localhost" or "localhost.localdomain") return false;
        if (name.EndsWith(".localhost", StringComparison.Ordinal)
            || name.EndsWith(".local", StringComparison.Ordinal)
            || name.EndsWith(".lan", StringComparison.Ordinal)
            || name.EndsWith(".internal", StringComparison.Ordinal)
            || name.EndsWith(".home.arpa", StringComparison.Ordinal))
        {
            return false;
        }

        return !IPAddress.TryParse(name, out var ip) || IsPublicAddress(ip);
    }

    private static bool IsPublicAddress(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();

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

    public static IEndpointRouteBuilder MapProxyExternalImageEndpoint(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/external/image-proxy", async (
            [FromQuery] string? url,
            [FromQuery] bool? forceRefresh,
            HttpContext context,
            [FromServices] IHttpClientFactory httpClientFactory,
            [FromServices] SearchCacheService searchCache,
            CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(url)
                || !Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri)
                || uri.Scheme is not ("http" or "https")
                || !IsAllowedRemoteHost(uri.Host))
            {
                return Results.BadRequest(new { error = "url must be an absolute image URL on a public host" });
            }

            var trimmed = url.Trim();
            context.Response.Headers.CacheControl = $"public, max-age={CacheControlMaxAgeSeconds}";

            // Fresh disk copy answers with zero network activity; the user's explicit refresh
            // (forceRefresh) skips the cache and re-downloads.
            if (forceRefresh != true)
            {
                var cached = await searchCache.TryGetImageAsync(trimmed, ct);
                if (cached is not null)
                {
                    return Results.Bytes(cached.Data, cached.ContentType);
                }
            }

            var client = httpClientFactory.CreateClient("ExternalImageProxy");
            using var request = ImageStorageService.CreateImageRequest(trimmed);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
            {
                // Error bodies are never cached: a 403/404/429 today says nothing about tomorrow.
                return Results.StatusCode((int)response.StatusCode);
            }

            // Buffer before returning: the using-disposed request/response die the moment this
            // lambda returns, while Results.Stream would only start copying the raw connection
            // stream afterwards — that raced the disposal and answered the browser with a 500.
            // The size limiter aborts bodies that exceed the image ceiling.
            using var buffered = new MemoryStream();
            await using var limited = new SizeLimitedStream(
                await response.Content.ReadAsStreamAsync(ct), MaxImageSizeBytes);
            await limited.CopyToAsync(buffered, ct);
            var bytes = buffered.ToArray();
            if (bytes.Length == 0)
            {
                return Results.StatusCode((int)response.StatusCode);
            }

            await searchCache.SetImageAsync(trimmed, bytes, ct);

            // Serve the sniffed signature when the bytes are a known format; the header type is
            // the fallback (and matches the cache's octet-stream case for exotic formats).
            var sniffed = SearchCacheService.DetectImageContentType(bytes);
            var contentType = sniffed != "application/octet-stream"
                ? sniffed
                : response.Content.Headers.ContentType?.ToString() ?? "image/jpeg";
            return Results.Bytes(bytes, contentType);
        })
        .WithTags("Внешний поиск / External")
        .WithSummary("Прокси и дисковый кэш обложек внешнего поиска (TTL 3 дня)");

        return app;
    }
}
