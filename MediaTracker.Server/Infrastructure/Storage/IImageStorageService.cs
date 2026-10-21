namespace MediaTracker.Server.Infrastructure.Storage;

public interface IImageStorageService
{
    /// <param name="folder">
    /// Sub-folder inside the title's asset directory. Only images that share a layout with the cover
    /// (the creator's photo or logo) belong here, so they reuse the same WebP pipeline instead of
    /// growing a second downloader.
    /// </param>
    Task<string?> SaveCoverAsync(
        string externalUrl,
        Guid itemId,
        CancellationToken ct = default,
        string folder = "cover");

    void DeleteCover(string? localCoverUrl);

    void DeleteMediaFolder(Guid mediaId);
}
