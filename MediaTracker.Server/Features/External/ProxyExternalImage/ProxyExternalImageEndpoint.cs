using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Features.External.ProxyExternalImage;

/// <summary>
/// Streams a whitelisted external cover image through the server. The SocialLib family serves its
/// covers from cover.imglib.info behind DDoS-Guard, which answers a plain browser &lt;img&gt;
/// request with 403 — the exact same URL downloads fine server-side once the browser-ish headers
/// from <see cref="ImageStorageService.CreateImageRequest"/> are attached. Search previews and the
/// other external panels route the guarded hosts through here instead of hotlinking them.
/// </summary>
public static class ProxyExternalImageEndpoint
{
    /// <summary>
    /// Only the hosts that actually block hotlinking are proxied; everything else keeps loading
    /// straight from its CDN. MangaDex serves its uploads behind a bot wall that answers a browser
    /// <img> with a challenge redirect, so its covers ride the proxy with a plain app UA.
    /// Keeping the list tight also pins the SSRF surface down: the endpoint will never fetch
    /// anything but these image hosts.
    /// </summary>
    private static readonly string[] AllowedHostSuffixes = ["imglib.info", "mangalib.me", "mangadex.org"];

    public static IEndpointRouteBuilder MapProxyExternalImageEndpoint(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/external/image-proxy", async (
            [FromQuery] string? url,
            [FromServices] IHttpClientFactory httpClientFactory,
            CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(url)
                || !Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri)
                || uri.Scheme is not ("http" or "https")
                || !AllowedHostSuffixes.Any(suffix => uri.Host.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)))
            {
                return Results.BadRequest(new { error = "url must be an absolute image URL on an allowed host" });
            }

            var client = httpClientFactory.CreateClient("ExternalImageProxy");
            using var request = ImageStorageService.CreateImageRequest(url.Trim());
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
            {
                return Results.StatusCode((int)response.StatusCode);
            }

            var contentType = response.Content.Headers.ContentType?.ToString() ?? "image/jpeg";

            // Buffer before returning: the using-disposed request/response die the moment this
            // lambda returns, while Results.Stream would only start copying the raw connection
            // stream afterwards — that raced the disposal and answered the browser with a 500.
            // Covers are capped at 10 MB upstream, so the memory copy is bounded.
            var buffered = new MemoryStream();
            await (await response.Content.ReadAsStreamAsync(ct)).CopyToAsync(buffered, ct);
            buffered.Seek(0, SeekOrigin.Begin);
            return Results.Stream(buffered, contentType);
        })
        .WithTags("Внешний поиск / External")
        .WithSummary("Прокси обложек с CDN, закрытых от хотлинка (DDoS-Guard)");

        return app;
    }
}
