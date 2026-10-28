using System.Diagnostics;
using MediaTracker.Server.Features.Media.MediaContract;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Webp;
using SixLabors.ImageSharp.Processing;

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
            using var response = await httpClient.GetAsync(externalUrl, HttpCompletionOption.ResponseHeadersRead, ct);
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
            using var image = await Image.LoadAsync(LimitStream(source), ct);

            await SaveWebpAsync(image, originalPath, MaxOriginalWidth, OriginalQuality, ct);

            // The thumb is what the grid renders. Cloned from the decoded image, so the download and
            // decode are still paid only once.
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
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or ImageFormatException or OversizedCoverException)
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
            using var response = await httpClient.GetAsync(externalUrl, HttpCompletionOption.ResponseHeadersRead, ct);
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
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or ImageFormatException or OversizedCoverException)
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

            using var image = await Image.LoadAsync(LimitStream(content), ct);

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
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or ImageFormatException or OversizedCoverException)
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
    /// Writes one WebP rendition, never upscaling: a source narrower than the cap is encoded as-is,
    /// because enlarging it would only add bytes and soften the poster.
    /// </summary>
    private static async Task SaveWebpAsync(
        Image image,
        string path,
        int maxWidth,
        int quality,
        CancellationToken ct)
    {
        var encoder = new WebpEncoder { Quality = quality };

        await using var fileStream = File.Create(path);
        if (image.Width <= maxWidth)
        {
            await image.SaveAsWebpAsync(fileStream, encoder, ct);
            return;
        }

        using var resized = image.Clone(context => context.Resize(new ResizeOptions
        {
            Mode = ResizeMode.Max,
            Size = new Size(maxWidth, 0)
        }));
        await resized.SaveAsWebpAsync(fileStream, encoder, ct);
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
