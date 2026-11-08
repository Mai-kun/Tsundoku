using System.Diagnostics;
using MediaTracker.Server.Features.Media.MediaContract;
using PhotoSauce.MagicScaler;
using PhotoSauce.NativeCodecs.Libjpeg;
using PhotoSauce.NativeCodecs.Libpng;
using PhotoSauce.NativeCodecs.Libwebp;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class ImageStorageService(
    HttpClient httpClient,
    AppPaths appPaths,
    ILogger<ImageStorageService> logger) : IImageStorageService
{
    static ImageStorageService()
    {
        // The native codecs are the only decoders/encoders MagicScaler has on Linux (the managed
        // fallbacks are Windows/WIC only), so they must be registered once before the first cover.
        CodecManager.Configure(codecs =>
        {
            codecs.UseLibjpeg();
            codecs.UseLibpng();
            codecs.UseLibwebp();
        });
    }

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

    // The gallery grid renders the thumb; 480px keeps a card crisp up to the 4-column breakpoint.
    private const int MaxGalleryThumbWidth = 480;
    private const int GalleryThumbQuality = 80;

    // The lightbox shows the original. Capped at 1920px, q85: a screenshot that fills a
    // full-screen window never needs more pixels, and re-encoding beyond it costs bytes.
    private const int MaxGalleryOriginalWidth = 1920;
    private const int GalleryOriginalQuality = 85;

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
            using var buffered = await BufferAsync(LimitStream(source), ct);

            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, originalPath, MaxOriginalWidth, OriginalQuality);

            // The thumb is what the grid renders. Resized from the same buffered source, so the
            // download is still paid only once — and no raw pixels are held between the two passes.
            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, thumbPath, MaxThumbWidth, ThumbQuality);

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
    /// Builds the image request with the headers each guarded CDN demands: the lib family wants a
    /// browser UA plus a mangalib referer (DDoS-Guard), while MangaDex wants the opposite — a
    /// browser-looking UA earns a bot-challenge redirect and a missing UA a 400, so only a plain
    /// app UA passes. Shared with the image-proxy endpoint so preview URLs get exactly the same
    /// treatment the cover downloader gives them.
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
            else if (host.EndsWith("mangadex.org", StringComparison.OrdinalIgnoreCase))
            {
                // The storage client ships a browser-ish default UA; drop it first so MangaDex
                // sees exactly one plain app agent (a doubled UA can still look browser-ish).
                request.Headers.Remove("User-Agent");
                request.Headers.TryAddWithoutValidation("User-Agent", "Tsundoku/1.0");
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

            using var buffered = await BufferAsync(LimitStream(content), ct);

            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, Path.Combine(variantDirectory, "original.webp"), MaxOriginalWidth, OriginalQuality);
            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, Path.Combine(variantDirectory, "thumb.webp"), MaxThumbWidth, ThumbQuality);

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
        DeleteMediaSubfolder(itemId, "covers", coverId);
    }

    public async Task<MediaGalleryItemDto?> SaveGalleryImageAsync(
        Stream content,
        Guid itemId,
        string? title = null,
        CancellationToken ct = default)
    {
        try
        {
            // Same short-hex folder scheme as the cover variants: cannot escape the media directory.
            var imgId = Guid.NewGuid().ToString("N")[..10];
            var imageDirectory = Path.Combine(appPaths.MediaDirectory, itemId.ToString(), "gallery", imgId);
            Directory.CreateDirectory(imageDirectory);

            using var buffered = await BufferAsync(LimitStream(content), ct);

            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, Path.Combine(imageDirectory, "original.webp"), MaxGalleryOriginalWidth, GalleryOriginalQuality);
            ct.ThrowIfCancellationRequested();
            SaveWebp(buffered, Path.Combine(imageDirectory, "thumb.webp"), MaxGalleryThumbWidth, GalleryThumbQuality);

            logger.LogInformation(
                "[Storage] Saved gallery screenshot {ImageId} for {MediaId} ({SizeKb} KB)",
                imgId,
                itemId,
                new FileInfo(Path.Combine(imageDirectory, "original.webp")).Length / 1024);

            return new MediaGalleryItemDto(
                imgId,
                $"{MediaAssetsRoutePrefix}{itemId}/gallery/{imgId}/thumb.webp",
                $"{MediaAssetsRoutePrefix}{itemId}/gallery/{imgId}/original.webp",
                title,
                DateTime.UtcNow);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or OversizedCoverException)
        {
            logger.LogWarning(ex, "[Storage] Failed to store gallery screenshot for {MediaId}, discarding", itemId);
            return null;
        }
    }

    public void DeleteGalleryImage(Guid itemId, string imgId)
    {
        DeleteMediaSubfolder(itemId, "gallery", imgId);
    }

    /// <summary>
    /// Removes one per-title sub-folder (a cover variant or a gallery screenshot). Idempotent,
    /// path-traversal safe: both ids and the item id must stay inside the media root.
    /// </summary>
    private void DeleteMediaSubfolder(Guid itemId, string subfolder, string folderId)
    {
        if (!IsSafeCoverId(folderId))
        {
            return;
        }

        var root = Path.GetFullPath(appPaths.MediaDirectory);
        var folder = Path.GetFullPath(Path.Combine(root, itemId.ToString(), subfolder, folderId));

        if (!folder.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (Directory.Exists(folder))
        {
            Directory.Delete(folder, recursive: true);
        }
    }

    private static Stream LimitStream(Stream source) =>
        new SizeLimitedStream(source, MaxCoverSizeBytes);

    /// <summary>
    /// Buffers the (non-seekable, size-limited) response stream into memory: MagicScaler needs to
    /// rewind for the header pass and the decode pass, and the 10 MB cap keeps that copy bounded.
    /// </summary>
    private static async Task<MemoryStream> BufferAsync(Stream source, CancellationToken ct)
    {
        var buffered = new MemoryStream();
        await source.CopyToAsync(buffered, ct);
        buffered.Seek(0, SeekOrigin.Begin); // CopyToAsync leaves the stream at its end
        return buffered;
    }

    /// <summary>
    /// Writes one WebP rendition, never upscaling: a source narrower than the cap is encoded as-is,
    /// because enlarging it would only add bytes and soften the poster. Dimensions are read from
    /// the header without decoding raw pixels, so the scaler works at native resolution only once
    /// per rendition and no full-size bitmap is ever held in managed memory.
    /// </summary>
    private static void SaveWebp(Stream sourceStream, string outputPath, int maxWidth, int quality)
    {
        sourceStream.Position = 0;

        // Читаем размеры без декодирования сырых пикселей
        var fileInfo = ImageFileInfo.Load(sourceStream);
        var frame = fileInfo.Frames[0];
        var targetWidth = frame.Width > maxWidth ? maxWidth : frame.Width;

        sourceStream.Position = 0;
        using var outputStream = File.Create(outputPath);

        var settings = new ProcessImageSettings
        {
            Width = targetWidth,
            ResizeMode = CropScaleMode.Max,
        };
        settings.TrySetEncoderFormat(ImageMimeTypes.Webp);

        try
        {
            settings.EncoderOptions = new WebpLossyEncoderOptions { Quality = quality };
        }
        catch
        {
            // Фоллбэк на дефолтные опции энкодера, если тип опций недоступен
        }

        try
        {
            MagicImageProcessor.ProcessImage(sourceStream, outputStream, settings);
        }
        catch (Exception ex) when (ex is not IOException and not OperationCanceledException)
        {
            // Unsupported/corrupt input and codec failures must reach the existing catch chain,
            // which already logs them and returns null instead of crashing the request.
            throw new IOException($"Failed to process {frame.Width}x{frame.Height} image into WebP: {outputPath}.", ex);
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
