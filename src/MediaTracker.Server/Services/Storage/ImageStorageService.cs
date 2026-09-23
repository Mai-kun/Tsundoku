using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Services.Storage;

public sealed class ImageStorageService(
    HttpClient httpClient,
    IHostEnvironment environment,
    ILogger<ImageStorageService> logger) : IImageStorageService
{
    private const string CoversRoutePrefix = "/covers/";

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

            var extension = ResolveExtension(response.Content.Headers.ContentType?.MediaType);
            var coversPath = GetCoversPath();
            Directory.CreateDirectory(coversPath);

            var fileName = $"{itemId}{extension}";
            var filePath = Path.Combine(coversPath, fileName);

            await using var source = await response.Content.ReadAsStreamAsync(ct);
            await using var destination = File.Create(filePath);
            await source.CopyToAsync(destination, ct);

            return $"{CoversRoutePrefix}{fileName}";
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or IOException)
        {
            logger.LogWarning(ex, "Failed to download cover from {ExternalUrl}, keeping external URL", externalUrl);
            return externalUrl;
        }
    }

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

    private string GetCoversPath() => Path.Combine(environment.ContentRootPath, "data", "covers");

    private static string ResolveExtension(string? mediaType) => mediaType?.ToLowerInvariant() switch
    {
        "image/png" => ".png",
        "image/webp" => ".webp",
        _ => ".jpg",
    };
}
