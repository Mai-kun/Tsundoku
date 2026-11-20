using System.Collections.Concurrent;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Features.External.ProxyExternalImage;

/// <summary>
/// Outcome of a single-flight CDN download: the final cache path on success, the upstream status
/// code (or a mapped 413/502/504) on failure. Nothing but a fully downloaded body ever lands in
/// the cache.
/// </summary>
internal sealed record ProxyImageDownload(bool Success, int StatusCode, string? CachePath);

/// <summary>
/// Streams an external cover image through the server. Several sources (the SocialLib family on
/// cover.imglib.info behind DDoS-Guard, MangaDex's bot-walled uploads CDN) answer a plain browser
/// &lt;img&gt; request with 403 — the same URLs download fine server-side once the browser-ish
/// headers from <see cref="ImageStorageService.CreateImageRequest"/> are attached. Every external
/// search preview routes through this endpoint, so successful downloads also land in the disk
/// cache (<see cref="SearchCacheService"/>, three-day TTL): a repeat preview is streamed straight
/// from the local file with zero requests to the CDN. Nothing is buffered: both the download and
/// the response path flow through <c>FileStream</c>s, so no image bytes ever sit in a byte[].
/// </summary>
public static class ProxyExternalImageEndpoint
{
    /// <summary>
    /// Hard ceiling for one proxied image; the stream wrapper aborts anything larger, so a
    /// misbehaving host cannot push an unbounded body into the disk cache.
    /// </summary>
    internal const long MaxImageSizeBytes = 10 * 1024 * 1024;

    /// <summary>Own deadline for the shared download task, independent of any one client's request.</summary>
    private static readonly TimeSpan DownloadTimeout = TimeSpan.FromSeconds(15);

    /// <summary>
    /// Browser-side freshness hint, aligned with the server-side TTL: after three days the
    /// browser asks the server again, which either serves a fresh cache file or re-downloads.
    /// </summary>
    private const int CacheControlMaxAgeSeconds = 72 * 60 * 60;

    /// <summary>
    /// Single-flight dedup for parallel downloads of the same URL: the first caller starts the
    /// shared task, everyone else awaits it instead of paying the CDN a second time (the exact
    /// race the search grid produces — several results sharing one cover URL). Unconditional
    /// removal in the caller's finally: a torn removal only risks a rare duplicate download,
    /// never a lost result — waiters hold their task reference directly.
    /// </summary>
    private static readonly ConcurrentDictionary<string, Lazy<Task<ProxyImageDownload>>> InFlightDownloads =
        new(StringComparer.Ordinal);

    /// <summary>
    /// Only public internet hosts are fetchable. The endpoint fetches whatever URL the search
    /// results reference, so the guard moved from a host whitelist to the SSRF minimum: no
    /// loopback, private, link-local or otherwise internal targets — the proxy must never be
    /// turned into a port-scanner for the local network. Единая логика с прокси-маршрутизатором:
    /// <see cref="Proxy.ProxyAddressGuard.IsPublicHost"/> (те же внутренние суффиксы и диапазоны).
    /// </summary>
    internal static bool IsAllowedRemoteHost(string host) => ProxyAddressGuard.IsPublicHost(host);

    /// <summary>
    /// Downloads an image into the cache streaming-only: the <see cref="SizeLimitedStream"/>
    /// body goes straight into the temp <c>FileStream</c> (<see cref="FileMode.CreateNew"/>),
    /// then one atomic rename commits it. No MemoryStream, no byte[] — an oversized or failed
    /// download leaves nothing behind. Runs on its own 15 s deadline, not on any client's
    /// CancellationToken, so a waiting coalesced caller cannot abort the shared download.
    /// </summary>
    internal static async Task<ProxyImageDownload> DownloadAndCacheImageAsync(
        IHttpClientFactory httpClientFactory,
        SearchCacheService searchCache,
        string url)
    {
        using var timeout = new CancellationTokenSource(DownloadTimeout);
        string? tempPath = null;
        try
        {
            var client = httpClientFactory.CreateClient("ExternalImageProxy");
            using var request = ImageStorageService.CreateImageRequest(url);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                // Error bodies are never cached: a 403/404/429 today says nothing about tomorrow.
                return new ProxyImageDownload(false, (int)response.StatusCode, null);
            }

            await using var limited = new SizeLimitedStream(
                await response.Content.ReadAsStreamAsync(timeout.Token), MaxImageSizeBytes);
            await using var tempStream = searchCache.OpenImageTempWriteStream(url);
            tempPath = tempStream.Name;
            await limited.CopyToAsync(tempStream, timeout.Token);
            await tempStream.FlushAsync(timeout.Token);
            await tempStream.DisposeAsync();

            // An empty body is not a cacheable cover — the upstream answered 200 with nothing.
            if (new FileInfo(tempPath).Length == 0)
            {
                searchCache.DiscardImageTemp(tempPath);
                tempPath = null;
                return new ProxyImageDownload(false, (int)response.StatusCode, null);
            }

            var finalPath = searchCache.CommitImage(tempPath, url);
            tempPath = null;
            return new ProxyImageDownload(true, (int)response.StatusCode, finalPath);
        }
        catch (OversizedCoverException)
        {
            if (tempPath is not null) searchCache.DiscardImageTemp(tempPath);
            return new ProxyImageDownload(false, 413, null);
        }
        catch (OperationCanceledException)
        {
            // Own timeout only: client cancellations never reach this shared task.
            if (tempPath is not null) searchCache.DiscardImageTemp(tempPath);
            return new ProxyImageDownload(false, 504, null);
        }
        catch (Exception)
        {
            if (tempPath is not null) searchCache.DiscardImageTemp(tempPath);
            return new ProxyImageDownload(false, 502, null);
        }
    }

    /// <summary>
    /// Opens the cached file for reading and returns a streaming result. The returned stream is
    /// deliberately NOT wrapped in a using: Kestrel disposes it after the response body is
    /// copied. The MIME type is sniffed from the first bytes of the file itself, so the served
    /// Content-Type always matches the bytes, whatever the CDN claimed.
    /// </summary>
    private static async Task<IResult> ServeCachedFileAsync(string path, CancellationToken ct)
    {
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, useAsync: true);
        try
        {
            var signature = new byte[12];
            var read = 0;
            int chunk;
            while (read < signature.Length && (chunk = await stream.ReadAsync(signature.AsMemory(read), ct)) > 0)
            {
                read += chunk;
            }

            stream.Seek(0, SeekOrigin.Begin);
            return Results.Stream(stream, SearchCacheService.DetectImageContentType(signature.AsSpan(0, read)));
        }
        catch
        {
            await stream.DisposeAsync();
            throw;
        }
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
                var cachedPath = searchCache.TryGetFreshImagePath(trimmed);
                if (cachedPath is not null)
                {
                    try
                    {
                        return await ServeCachedFileAsync(cachedPath, ct);
                    }
                    catch (FileNotFoundException)
                    {
                        // A sweep raced between the freshness check and this open: fall through
                        // to the network instead of answering the browser with a 500.
                    }
                }
            }

            var shared = InFlightDownloads.GetOrAdd(
                trimmed,
                _ => new Lazy<Task<ProxyImageDownload>>(
                    () => DownloadAndCacheImageAsync(httpClientFactory, searchCache, trimmed),
                    LazyThreadSafetyMode.ExecutionAndPublication));

            ProxyImageDownload download;
            try
            {
                // Waiting respects this client's cancellation; the shared download itself does
                // not depend on it.
                download = await shared.Value.WaitAsync(ct);
            }
            finally
            {
                InFlightDownloads.TryRemove(trimmed, out _);
            }

            if (!download.Success)
            {
                return Results.StatusCode(download.StatusCode);
            }

            try
            {
                return await ServeCachedFileAsync(download.CachePath!, ct);
            }
            catch (FileNotFoundException)
            {
                // Committed, then swept/evicted before we could open it — a miss, not an error.
                return Results.StatusCode(502);
            }
        })
        .WithTags("Внешний поиск / External")
        .WithSummary("Прокси и дисковый кэш обложек внешнего поиска (TTL 3 дня, стриминг)");

        return app;
    }
}
