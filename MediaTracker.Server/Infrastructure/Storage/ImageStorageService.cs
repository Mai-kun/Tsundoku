using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;

namespace MediaTracker.Server.Infrastructure.Storage;

public sealed class ImageStorageService(
    HttpClient httpClient,
    AppPaths appPaths,
    ILogger<ImageStorageService> logger) : IImageStorageService
{
    private const string CoversRoutePrefix = "/covers/";
    private const int MaxCoverWidth = 400;
    private const long MaxCoverSizeBytes = 10 * 1024 * 1024; // 10 MB limit

    public async Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(externalUrl))
        {
            return externalUrl;
        }

        try
        {
            using var response = await httpClient.GetAsync(externalUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();

            if (IsOversized(response))
            {
                logger.LogWarning("Cover image at {ExternalUrl} exceeds size limit of {MaxBytes} bytes", externalUrl, MaxCoverSizeBytes);
                return externalUrl;
            }

            var coversPath = GetCoversPath();
            Directory.CreateDirectory(coversPath);

            var fileName = $"{itemId}.webp";
            var filePath = Path.Combine(coversPath, fileName);

            await using var source = await response.Content.ReadAsStreamAsync(ct);
            using var image = await Image.LoadAsync(LimitStream(source), ct);

            if (image.Width > MaxCoverWidth)
            {
                image.Mutate(context => context.Resize(new ResizeOptions
                {
                    Mode = ResizeMode.Max,
                    Size = new Size(MaxCoverWidth, 0)
                }));
            }

            await image.SaveAsWebpAsync(filePath, ct);

            return $"{CoversRoutePrefix}{fileName}";
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException or ImageFormatException or OversizedCoverException)
        {
            logger.LogWarning(ex, "Failed to download cover from {ExternalUrl}, keeping external URL", externalUrl);
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
        if (string.IsNullOrWhiteSpace(localCoverUrl) ||
            !localCoverUrl.StartsWith(CoversRoutePrefix, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var fileName = localCoverUrl[CoversRoutePrefix.Length..];

        if (fileName.Length == 0 || fileName.Contains('/') || fileName.Contains('\\'))
        {
            return;
        }

        var coversRoot = Path.GetFullPath(GetCoversPath());
        var filePath = Path.GetFullPath(Path.Combine(coversRoot, fileName));

        if (!filePath.StartsWith(coversRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (File.Exists(filePath))
        {
            File.Delete(filePath);
        }
    }

    private string GetCoversPath() => appPaths.CoversDirectory;
}
