using System.Diagnostics;
using MediaTracker.Server.Features.Media.MediaContract;
using SkiaSharp;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class ImageStorageService(
    HttpClient httpClient,
    AppPaths appPaths,
    ILogger<ImageStorageService> logger) : IImageStorageService
{
    private const string CoversRoutePrefix = "/covers/";
    private const string MediaAssetsRoutePrefix = "/media-assets/";

    // The thumb is what the grid renders. 360px keeps a card crisp on a retina phone and on the
    // larger grid breakpoints; anything below that upsamples into visible mush on a desktop.
    private const int MaxThumbWidth = 360;
    private const int ThumbQuality = 82;

    // The detail page poster is the only place a cover is shown near full size, so it gets the
    // quality budget. Capped at 1200px: posters are portrait 2:3, so this is the width a large
    // monitor can actually fill, and re-encoding beyond it would only cost bytes.
    private const int MaxOriginalWidth = 1200;
    private const int OriginalQuality = 88;

    private const long MaxCoverSizeBytes = 10 * 1024 * 1024; // 10 MB limit

    public async Task<string?> SaveCoverAsync(
        string externalUrl,
        Guid itemId,
        CancellationToken ct = default,
        string folder = "cover")
    {
        if (string.IsNullOrWhiteSpace(externalUrl))
        {
            return externalUrl;
        }

        var sw = Stopwatch.StartNew();
        try
        {
            using var request = CreateImageRequest(externalUrl);
            using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();

            if (IsOversized(response))
            {
                logger.LogWarning("Cover image at {ExternalUrl} exceeds size limit of {MaxBytes} bytes", externalUrl, MaxCoverSizeBytes);
                return null;
            }

            // One path, one URL: <title>/<folder>/... is exactly what the returned URL and the
            // /media-assets static route resolve, so nesting another "cover" under GetCoverDirectory
            // used to write cover/cover/ while the browser asked for cover/ and got a 404.
            var coverDirectory = Path.Combine(appPaths.MediaDirectory, itemId.ToString(), folder);
            Directory.CreateDirectory(coverDirectory);

            var originalPath = Path.Combine(coverDirectory, "original.webp");
            var thumbPath = Path.Combine(coverDirectory, "thumb.webp");

            await using var source = await response.Content.ReadAsStreamAsync(ct);
            using var image = await DecodeBitmapAsync(LimitStream(source), ct);

            await SaveWebpAsync(image, originalPath, MaxOriginalWidth, OriginalQuality, ct);

            // The thumb is what the grid renders. Resized from the same decoded bitmap, so the
            // download and decode are still paid only once.
            await SaveWebpAsync(image, thumbPath, MaxThumbWidth, ThumbQuality, ct);

            sw.Stop();

            var sizeKb = new FileInfo(originalPath).Length / 1024;
            logger.LogInformation(
                "[Storage] Downloaded {Type} for {MediaId} ({SizeKb} KB, {ElapsedMs}ms)",
                folder,
                itemId,
                sizeKb,
                sw.ElapsedMilliseconds);

            return $"{MediaAssetsRoutePrefix}{itemId}/{folder}/thumb.webp";
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or OversizedCoverException)
        {
            sw.Stop();
            logger.LogWarning(
                ex,
                "[Storage] Failed to download cover for {MediaId} from {ExternalUrl} after {ElapsedMs}ms, discarding",
                itemId,
                externalUrl,
                sw.ElapsedMilliseconds);
            return null;
        }
    }

    /// <summary>
    /// A chunked response reports no Content-Length, so the header check alone let an unbounded
    /// body through. This caps the bytes actually read regardless of what the server declares.
    /// </summary>
    private bool IsOversized(HttpResponseMessage response) =>
        response.Content.Headers.ContentLength is { } declared && declared > MaxCoverSizeBytes;

    /// <summary>Variant ids are folder names; only a short hex chunk must ever reach the filesystem.</summary>
    private static bool IsSafeCoverId(string coverId) =>
        coverId.Length > 0 && coverId.Length <= 40 && coverId.All(char.IsAsciiLetterOrDigit);

    /// <summary>
    /// Builds the image request with the headers the DDoS-guarded lib CDNs demand (a browser UA
    /// plus a mangalib referer). Shared with the image-proxy endpoint so preview URLs get exactly
    /// the same treatment the cover downloader gives them.
    /// </summary>
    public static HttpRequestMessage CreateImageRequest(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            var host = uri.Host;
            if (host.EndsWith("imglib.info", StringComparison.OrdinalIgnoreCase)
                || host.EndsWith("mangalib.me", StringComparison.OrdinalIgnoreCase))
            {
                request.Headers.TryAddWithoutValidation("Referer", "https://mangalib.me/");
                request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36");
            }
        }
        return request;
    }

    public async Task<MediaCoverItemDto?> SaveCoverVariantAsync(
        string externalUrl,
        Guid itemId,
        string? source = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(externalUrl))
        {
            return null;
        }

        var sw = Stopwatch.StartNew();
        try
        {
            using var request = CreateImageRequest(externalUrl);
            using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();

            if (IsOversized(response))
            {
                logger.LogWarning("Cover image at {ExternalUrl} exceeds size limit of {MaxBytes} bytes", externalUrl, MaxCoverSizeBytes);
                return null;
            }

            await using var sourceStream = await response.Content.ReadAsStreamAsync(ct);
            return await SaveCoverVariantAsync(sourceStream, itemId, source, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or OversizedCoverException)
        {
            sw.Stop();
            logger.LogWarning(
                ex,
                "[Storage] Failed to download cover variant for {MediaId} from {ExternalUrl} after {ElapsedMs}ms, keeping current covers",
                itemId,
                externalUrl,
                sw.ElapsedMilliseconds);
            return null;
        }
    }

    public async Task<MediaCoverItemDto?> SaveCoverVariantAsync(
        Stream content,
        Guid itemId,
        string? source = null,
        CancellationToken ct = default)
    {
        try
        {
            // A short hex chunk keeps the folder name short and cannot escape the media directory.
            var coverId = Guid.NewGuid().ToString("N")[..10];
            var variantDirectory = Path.Combine(appPaths.MediaDirectory, itemId.ToString(), "covers", coverId);
            Directory.CreateDirectory(variantDirectory);

            using var image = await DecodeBitmapAsync(LimitStream(content), ct);

            await SaveWebpAsync(image, Path.Combine(variantDirectory, "original.webp"), MaxOriginalWidth, OriginalQuality, ct);
            await SaveWebpAsync(image, Path.Combine(variantDirectory, "thumb.webp"), MaxThumbWidth, ThumbQuality, ct);

            logger.LogInformation(
                "[Storage] Saved cover variant {CoverId} for {MediaId} ({SizeKb} KB)",
                coverId,
                itemId,
                new FileInfo(Path.Combine(variantDirectory, "original.webp")).Length / 1024);

            return new MediaCoverItemDto(
                coverId,
                $"{MediaAssetsRoutePrefix}{itemId}/covers/{coverId}/thumb.webp",
                $"{MediaAssetsRoutePrefix}{itemId}/covers/{coverId}/original.webp",
                source,
                DateTime.UtcNow);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or OversizedCoverException)
        {
            logger.LogWarning(ex, "[Storage] Failed to store cover variant for {MediaId}, discarding", itemId);
            return null;
        }
    }

    public void DeleteCoverVariant(Guid itemId, string coverId)
    {
        if (!IsSafeCoverId(coverId))
        {
            return;
        }

        var root = Path.GetFullPath(appPaths.MediaDirectory);
        var variantFolder = Path.GetFullPath(Path.Combine(root, itemId.ToString(), "covers", coverId));

        if (!variantFolder.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (Directory.Exists(variantFolder))
        {
            Directory.Delete(variantFolder, recursive: true);
        }
    }

    private static Stream LimitStream(Stream source) =>
        new SizeLimitedStream(source, MaxCoverSizeBytes);

    /// <summary>
    /// Decodes an image into a bitmap. The limited stream is non-seekable, so it is buffered into
    /// memory first: the codec must rewind for a full decode, and the 10 MB cap keeps that copy
    /// bounded. Decode failures surface as IOException so the existing catch chain logs them.
    /// </summary>
    private static async Task<SKBitmap> DecodeBitmapAsync(Stream source, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        using var buffered = new MemoryStream();
        await source.CopyToAsync(buffered, ct);
        buffered.Seek(0, SeekOrigin.Begin); // CopyToAsync leaves the stream at its end

        using var codec = SKCodec.Create(buffered);
        if (codec is null)
        {
            throw new IOException("Unsupported or corrupt image data: no codec could decode the stream.");
        }

        var bitmap = SKBitmap.Decode(codec);
        if (bitmap is null)
        {
            throw new IOException($"Failed to decode {codec.EncodedFormat} image data.");
        }

        return bitmap;
    }

    /// <summary>
    /// Writes one WebP rendition, never upscaling: a source narrower than the cap is encoded as-is,
    /// because enlarging it would only add bytes and soften the poster.
    /// </summary>
    private static async Task SaveWebpAsync(
        SKBitmap source,
        string path,
        int maxWidth,
        int quality,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        var width = source.Width;
        var height = source.Height;

        SKBitmap bitmapToEncode = source;
        SKBitmap? resizedBitmap = null;

        if (width > maxWidth)
        {
            var scale = (float)maxWidth / width;
            var targetWidth = maxWidth;
            var targetHeight = Math.Max(1, (int)Math.Round(height * scale));

            resizedBitmap = new SKBitmap(targetWidth, targetHeight, source.ColorType, source.AlphaType);
            source.ScalePixels(resizedBitmap, SKFilterQuality.High);
            bitmapToEncode = resizedBitmap;
        }

        try
        {
            using var image = SKImage.FromBitmap(bitmapToEncode);
            using var data = image.Encode(SKEncodedImageFormat.Webp, quality);
            if (data is null)
            {
                throw new IOException("Failed to encode image to WebP format.");
            }

            await using var fileStream = File.Create(path);
            data.SaveTo(fileStream);
        }
        finally
        {
            resizedBitmap?.Dispose();
        }
    }

    public void DeleteCover(string? localCoverUrl)
    {
        if (string.IsNullOrWhiteSpace(localCoverUrl))
        {
            return;
        }

        var legacy = localCoverUrl.StartsWith(CoversRoutePrefix, StringComparison.OrdinalIgnoreCase);
        var current = localCoverUrl.StartsWith(MediaAssetsRoutePrefix, StringComparison.OrdinalIgnoreCase);

        // Rows saved before the per-title folders existed still point at /covers/{id}.webp, so both
        // prefixes have to resolve or deleting those titles would strand their files on disk.
        if (legacy)
        {
            var fileName = localCoverUrl[CoversRoutePrefix.Length..];

            if (fileName.Length == 0 || fileName.Contains('/') || fileName.Contains('\\'))
            {
                return;
            }

            DeleteFile(Path.Combine(GetCoversPath(), fileName), Path.GetFullPath(GetCoversPath()));
            return;
        }

        if (current)
        {
            var relative = localCoverUrl[MediaAssetsRoutePrefix.Length..];
            DeleteFile(
                Path.Combine(appPaths.MediaDirectory, relative),
                Path.GetFullPath(appPaths.MediaDirectory));
        }
    }

    /// <summary>
    /// Removes the whole per-title folder. A title owns more than its cover — achievement icons land
    /// next to it — so deleting file by file would leave orphans nothing ever asks about again.
    /// </summary>
    public void DeleteMediaFolder(Guid mediaId)
    {
        var root = Path.GetFullPath(appPaths.MediaDirectory);
        var folder = Path.GetFullPath(Path.Combine(root, mediaId.ToString()));

        if (!folder.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (Directory.Exists(folder))
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    private static void DeleteFile(string filePath, string allowedRoot)
    {
        var fullPath = Path.GetFullPath(filePath);

        if (!fullPath.StartsWith(allowedRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (File.Exists(fullPath))
        {
            File.Delete(fullPath);
        }
    }

    private string GetCoversPath() => appPaths.CoversDirectory;
}
