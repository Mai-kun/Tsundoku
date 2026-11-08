using System.Text.Json;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.Media.MediaContract;

/// <summary>
/// One file attached to a title (book, archive, save). <see cref="Id"/> doubles as the on-disk file
/// name inside <c>media/{itemId}/files/</c> — it is produced by the same sanitising code that wrote
/// the file, so reconstructing the path from the id can never escape that folder.
/// </summary>
public sealed record MediaAttachmentDto(
    string Id,
    string FileName,
    long FileSizeBytes,
    string? ContentType,
    DateTime AddedAt);

/// <summary>
/// One user screenshot of the gallery. <see cref="ThumbUrl"/> is what the grid renders;
/// <see cref="OriginalUrl"/> is the same folder's full-size rendition for the lightbox,
/// exactly the pair the cover gallery stores.
/// </summary>
public sealed record MediaGalleryItemDto(
    string Id,
    string ThumbUrl,
    string OriginalUrl,
    string? Title,
    DateTime AddedAt);

/// <summary>
/// Reads and writes the <c>AttachmentsJson</c> / <c>GalleryJson</c> columns. Same contract as
/// <see cref="MediaCoverCollection"/>: a list written by one slice must survive whatever writes the
/// row next, and the stored shape is exactly the serialised DTO list.
/// </summary>
public static class MediaAttachmentCollection
{
    public static List<MediaAttachmentDto> ParseAttachments(string? attachmentsJson) =>
        [.. MediaJsonCache.Deserialize<MediaAttachmentDto>(attachmentsJson)];

    public static List<MediaGalleryItemDto> ParseGallery(string? galleryJson) =>
        [.. MediaJsonCache.Deserialize<MediaGalleryItemDto>(galleryJson)];

    public static string? SerializeAttachments(IReadOnlyList<MediaAttachmentDto> attachments) =>
        attachments.Count == 0
            ? null
            : JsonSerializer.Serialize(attachments, AppJsonSerializerContext.Default.IReadOnlyListMediaAttachmentDto);

    public static string? SerializeGallery(IReadOnlyList<MediaGalleryItemDto> gallery) =>
        gallery.Count == 0
            ? null
            : JsonSerializer.Serialize(gallery, AppJsonSerializerContext.Default.IReadOnlyListMediaGalleryItemDto);
}
