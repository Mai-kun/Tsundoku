using MediaTracker.Server.Features.Media.MediaContract;

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

    /// <summary>
    /// Downloads a cover and stores it as a NEW gallery variant under
    /// <c>media/{itemId}/covers/{coverId}/</c>, leaving any existing files untouched. Returns null
    /// when the download or the decode failed, so the caller keeps its current cover.
    /// </summary>
    Task<MediaCoverItemDto?> SaveCoverVariantAsync(
        string externalUrl,
        Guid itemId,
        string? source = null,
        CancellationToken ct = default);

    /// <summary>Same as the URL overload, but the image comes from an uploaded file.</summary>
    Task<MediaCoverItemDto?> SaveCoverVariantAsync(
        Stream content,
        Guid itemId,
        string? source = null,
        CancellationToken ct = default);

    /// <summary>Deletes one gallery variant's folder on disk. Idempotent, path-traversal safe.</summary>
    void DeleteCoverVariant(Guid itemId, string coverId);

    /// <summary>
    /// Stores an uploaded screenshot as a NEW gallery entry under
    /// <c>media/{itemId}/gallery/{imgId}/</c> as original.webp (max 1920px, q85) and thumb.webp
    /// (max 480px, q80). Returns null when the decode failed, so the caller keeps its gallery.
    /// </summary>
    Task<MediaGalleryItemDto?> SaveGalleryImageAsync(
        Stream content,
        Guid itemId,
        string? title = null,
        CancellationToken ct = default);

    /// <summary>Deletes one gallery screenshot's folder on disk. Idempotent, path-traversal safe.</summary>
    void DeleteGalleryImage(Guid itemId, string imgId);

    void DeleteCover(string? localCoverUrl);

    void DeleteMediaFolder(Guid mediaId);
}
