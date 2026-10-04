using System.Diagnostics;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class ImageStorageService(
    HttpClient httpClient,
    AppPaths appPaths,
    ILogger<ImageStorageService> logger) : IImageStorageService
{
    private const string CoversRoutePrefix = "/covers/";
    private const string MediaAssetsRoutePrefix = "/media-assets/";
    private const int MaxThumbWidth = 160;
    private const long MaxCoverSizeBytes = 10 * 1024 * 1024; // 10 MB limit

    public async Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default)
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
                return externalUrl;
            }

            var coverDirectory = GetCoverDirectory(itemId);
            Directory.CreateDirectory(coverDirectory);

            var originalPath = Path.Combine(coverDirectory, "original.webp");
            var thumbPath = Path.Combine(coverDirectory, "thumb.webp");

            await using var source = await response.Content.ReadAsStreamAsync(ct);
            using var image = await Image.LoadAsync(LimitStream(source), ct);

            await image.SaveAsWebpAsync(originalPath, ct);

            // The thumb is what the grid renders: a 400px poster per card is several times the bytes
            // for no visible gain at that size. Cloned from the decoded image, so the download and
            // decode are still paid only once.
            using var thumb = image.Clone(context => context.Resize(new ResizeOptions
            {
                Mode = ResizeMode.Max,
                Size = new Size(MaxThumbWidth, 0)
            }));
            await thumb.SaveAsWebpAsync(thumbPath, ct);

            sw.Stop();

            var sizeKb = new FileInfo(originalPath).Length / 1024;
            logger.LogInformation(
                "[Storage] Downloaded {Type} for {MediaId} ({SizeKb} KB, {ElapsedMs}ms)",
                "cover",
                itemId,
                sizeKb,
                sw.ElapsedMilliseconds);

            return $"{MediaAssetsRoutePrefix}{itemId}/cover/thumb.webp";
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
                "[Storage] Failed to download cover for {MediaId} from {ExternalUrl} after {ElapsedMs}ms, keeping external URL",
                itemId,
                externalUrl,
                sw.ElapsedMilliseconds);
            return externalUrl;
        }
    }

    /// <summary>
    /// A chunked response reports no Content-Length, so the header check alone let an unbounded
    /// body through. This caps the bytes actually read regardless of what the server declares.
    /// </summary>
    private bool IsOversized(HttpResponseMessage response) =>
        response.Content.Headers.ContentLength is { } declared && declared > MaxCoverSizeBytes;

    private static Stream LimitStream(Stream source) =>
        new SizeLimitedStream(source, MaxCoverSizeBytes);

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

    private string GetCoverDirectory(Guid mediaId) =>
        Path.Combine(appPaths.MediaDirectory, mediaId.ToString(), "cover");
}
