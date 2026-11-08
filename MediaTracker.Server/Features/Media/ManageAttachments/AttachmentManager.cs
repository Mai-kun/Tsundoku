using System.Diagnostics;
using System.Text;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Features.Media.ManageAttachments;

public interface IAttachmentManager
{
    /// <summary>Stores an uploaded file and returns the refreshed attachment list.</summary>
    Task<Result<IReadOnlyList<MediaAttachmentDto>>> AddFileAsync(Guid mediaId, IFormFile file, CancellationToken ct);

    /// <summary>Removes one file from disk and from the index; returns the refreshed list.</summary>
    Task<Result<IReadOnlyList<MediaAttachmentDto>>> DeleteFileAsync(Guid mediaId, string fileId, CancellationToken ct);

    /// <summary>Resolves a stored attachment back to its on-disk file for streaming.</summary>
    Task<Result<(MediaAttachmentDto Attachment, string FilePath)>> ResolveDownloadAsync(Guid mediaId, string fileId, CancellationToken ct);

    /// <summary>Opens the stored file in the OS program associated with its type.</summary>
    Task<Result<Unit>> OpenFileAsync(Guid mediaId, string fileId, CancellationToken ct);

    /// <summary>Stores an uploaded screenshot in the gallery and returns the created entry.</summary>
    Task<Result<MediaGalleryItemDto>> AddGalleryImageAsync(Guid mediaId, Stream content, string? title, CancellationToken ct);

    /// <summary>Removes one screenshot's folder and index entry; returns the updated card.</summary>
    Task<Result<MediaDetailDto>> DeleteGalleryImageAsync(Guid mediaId, string imgId, CancellationToken ct);

    /// <summary>Makes a gallery screenshot the title's active cover; returns the updated card.</summary>
    Task<Result<MediaDetailDto>> SetGalleryImageAsCoverAsync(Guid mediaId, string imgId, CancellationToken ct);
}

/// <summary>
/// Write side of the per-title file archive and the screenshot gallery. Files live as plain bytes
/// under <c>media/{id}/files/</c>, gallery screenshots as webp renditions under
/// <c>media/{id}/gallery/{imgId}/</c>; the row only carries the JSON index, exactly like the cover
/// gallery does. Writes stamp the row and invalidate the list cache the way a cover write does.
/// </summary>
public sealed class AttachmentManager(
    AppDbContext db,
    AppPaths appPaths,
    IImageStorageService imageStorage,
    ILogger<AttachmentManager> logger) : IAttachmentManager
{
    // Books and save archives run bigger than covers; matches the Kestrel request cap.
    private const long MaxAttachmentSizeBytes = 30 * 1024 * 1024;

    public async Task<Result<IReadOnlyList<MediaAttachmentDto>>> AddFileAsync(Guid mediaId, IFormFile file, CancellationToken ct)
    {
        if (file.Length == 0)
        {
            return Failure(Error.Validation("The uploaded file must not be empty."));
        }

        if (file.Length > MaxAttachmentSizeBytes)
        {
            return Failure(Error.Validation("The file exceeds the 30 MB size limit."));
        }

        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return NotFound(mediaId);
        }

        var sanitized = SanitizeFileName(file.FileName);

        // The id doubles as the on-disk name, so it is produced by the same sanitiser that wrote
        // the file and reconstructing media/{id}/files/{id} can never escape the folder.
        var attachmentId = $"{Guid.NewGuid():N}_{sanitized}";
        var filesDirectory = MediaFilesRoot(mediaId);
        Directory.CreateDirectory(filesDirectory);
        var filePath = Path.Combine(filesDirectory, attachmentId);

        try
        {
            await using var target = File.Create(filePath);
            await file.CopyToAsync(target, ct);
        }
        catch (IOException ex)
        {
            logger.LogWarning(ex, "[Attachments] Failed to write attachment for {MediaId}", mediaId);
            TryDelete(filePath);
            return Failure(Error.Validation("The file could not be stored on disk."));
        }

        var attachment = new MediaAttachmentDto(
            attachmentId,
            sanitized,
            new FileInfo(filePath).Length,
            file.ContentType is { Length: > 0 } contentType ? contentType : null,
            DateTime.UtcNow);

        var attachments = MediaAttachmentCollection.ParseAttachments(item.AttachmentsJson);
        attachments.Add(attachment);
        item.AttachmentsJson = MediaAttachmentCollection.SerializeAttachments(attachments);
        await SaveAsync(item);

        return Result<IReadOnlyList<MediaAttachmentDto>>.Success(attachments);
    }

    public async Task<Result<IReadOnlyList<MediaAttachmentDto>>> DeleteFileAsync(Guid mediaId, string fileId, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return NotFound(mediaId);
        }

        var attachments = MediaAttachmentCollection.ParseAttachments(item.AttachmentsJson);
        var removed = attachments.Find(attachment => attachment.Id == fileId);
        if (removed is null)
        {
            return Failure(Error.NotFound($"Attachment '{fileId}' was not found on media item '{mediaId}'."));
        }

        attachments.Remove(removed);
        item.AttachmentsJson = MediaAttachmentCollection.SerializeAttachments(attachments);
        TryDelete(Path.Combine(MediaFilesRoot(mediaId), removed.Id));
        await SaveAsync(item);

        return Result<IReadOnlyList<MediaAttachmentDto>>.Success(attachments);
    }

    public async Task<Result<(MediaAttachmentDto Attachment, string FilePath)>> ResolveDownloadAsync(Guid mediaId, string fileId, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return Result<(MediaAttachmentDto, string)>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));
        }

        var attachment = MediaAttachmentCollection.ParseAttachments(item.AttachmentsJson)
            .Find(candidate => candidate.Id == fileId);
        if (attachment is null)
        {
            return Result<(MediaAttachmentDto, string)>.Failure(
                Error.NotFound($"Attachment '{fileId}' was not found on media item '{mediaId}'."));
        }

        var root = Path.GetFullPath(MediaFilesRoot(mediaId));
        var filePath = Path.GetFullPath(Path.Combine(root, attachment.Id));
        if (!filePath.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || !File.Exists(filePath))
        {
            return Result<(MediaAttachmentDto, string)>.Failure(
                Error.NotFound($"The file behind attachment '{fileId}' is missing on disk."));
        }

        return Result<(MediaAttachmentDto, string)>.Success((attachment, filePath));
    }

    public async Task<Result<Unit>> OpenFileAsync(Guid mediaId, string fileId, CancellationToken ct)
    {
        var resolved = await ResolveDownloadAsync(mediaId, fileId, ct);
        if (!resolved.TryGetValue(out var found))
        {
            return Result<Unit>.Failure(resolved.Error!);
        }

        try
        {
            OpenInSystemApp(found.FilePath);
            return Result<Unit>.Success(Unit.Value);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "[Attachments] Failed to open {File} in a system app", found.FilePath);
            return Result<Unit>.Failure(Error.Unavailable(
                $"The system refused to open '{found.Attachment.FileName}': {ex.Message}"));
        }
    }

    /// <summary>
    /// Hands the file to whatever program the OS associates with its type: the shell on Windows,
    /// the `open` verb on macOS, xdg-open on Linux. The process outlives the request on purpose —
    /// the user's reader or editor is not a child of the server.
    /// </summary>
    private static void OpenInSystemApp(string fullPath)
    {
        if (OperatingSystem.IsWindows())
        {
            Process.Start(new ProcessStartInfo(fullPath) { UseShellExecute = true });
            return;
        }

        if (OperatingSystem.IsMacOS())
        {
            Process.Start("open", fullPath);
            return;
        }

        var launcher = new ProcessStartInfo
        {
            FileName = "xdg-open",
            UseShellExecute = false,
        };
        launcher.ArgumentList.Add(fullPath);
        Process.Start(launcher);
    }

    public async Task<Result<MediaGalleryItemDto>> AddGalleryImageAsync(Guid mediaId, Stream content, string? title, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return Result<MediaGalleryItemDto>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));
        }

        var entry = await imageStorage.SaveGalleryImageAsync(content, mediaId, title, ct);
        if (entry is null)
        {
            return Result<MediaGalleryItemDto>.Failure(
                Error.Validation("The image could not be decoded. Supported are the usual raster formats (10 MB max)."));
        }

        var gallery = MediaAttachmentCollection.ParseGallery(item.GalleryJson);
        gallery.Add(entry);
        item.GalleryJson = MediaAttachmentCollection.SerializeGallery(gallery);
        await SaveAsync(item);

        return Result<MediaGalleryItemDto>.Success(entry);
    }

    public async Task<Result<MediaDetailDto>> DeleteGalleryImageAsync(Guid mediaId, string imgId, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));
        }

        var gallery = MediaAttachmentCollection.ParseGallery(item.GalleryJson);
        var removed = gallery.Find(entry => entry.Id == imgId);
        if (removed is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Gallery image '{imgId}' was not found on media item '{mediaId}'."));
        }

        gallery.Remove(removed);
        item.GalleryJson = MediaAttachmentCollection.SerializeGallery(gallery);
        imageStorage.DeleteGalleryImage(mediaId, removed.Id);
        await SaveAsync(item);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    public async Task<Result<MediaDetailDto>> SetGalleryImageAsCoverAsync(Guid mediaId, string imgId, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));
        }

        var entry = MediaAttachmentCollection.ParseGallery(item.GalleryJson)
            .Find(candidate => candidate.Id == imgId);
        if (entry is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Gallery image '{imgId}' was not found on media item '{mediaId}'."));
        }

        var root = Path.GetFullPath(Path.Combine(Path.GetFullPath(appPaths.MediaDirectory), mediaId.ToString(), "gallery"));
        var imagePath = Path.GetFullPath(Path.Combine(root, entry.Id, "original.webp"));
        if (!imagePath.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || !File.Exists(imagePath))
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"The screenshot '{imgId}' is missing on disk."));
        }

        // Re-encode through the standard cover pipeline, so the new poster lands in the cover
        // gallery as a regular variant (visible in the cover manager, removable like any other).
        MediaCoverCollection.EnsureLegacyCoverRegistered(item);
        await using var source = File.OpenRead(imagePath);
        var variant = await imageStorage.SaveCoverVariantAsync(source, mediaId, "gallery", ct);
        if (variant is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.Validation("The screenshot could not be converted into a cover."));
        }

        var covers = MediaCoverCollection.Parse(item.CoversJson);
        covers.Add(variant);
        item.CoversJson = MediaCoverCollection.Serialize(covers);
        item.CoverUrl = variant.ThumbUrl;

        // A cover choice is a display decision, not a manual metadata edit (same rule as SelectCover).
        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item);
        MediaListCache.Invalidate();

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    private async Task SaveAsync(MediaItem item)
    {
        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item);
        MediaListCache.Invalidate();
    }

    private string MediaFilesRoot(Guid mediaId) =>
        Path.Combine(Path.GetFullPath(appPaths.MediaDirectory), mediaId.ToString(), "files");

    /// <summary>
    /// Strips every path component and filesystem-hostile character. The result travels inside the
    /// attachment id, so a hostile name must never be able to carry <c>../</c> onto the disk path.
    /// </summary>
    private static string SanitizeFileName(string fileName)
    {
        var name = Path.GetFileName(fileName.Replace('\\', '/'));
        var builder = new StringBuilder(name.Length);
        foreach (var ch in name)
        {
            builder.Append(Array.IndexOf(Path.GetInvalidFileNameChars(), ch) >= 0 ? '_' : ch);
        }

        var cleaned = builder.ToString().Trim();
        if (cleaned.Length == 0)
        {
            return "file";
        }

        // Keep the extension readable but cap the total: the id carries the whole name on disk.
        const int maxLength = 120;
        if (cleaned.Length <= maxLength)
        {
            return cleaned;
        }

        var extension = Path.GetExtension(cleaned);
        return string.IsNullOrEmpty(extension)
            ? cleaned[..maxLength]
            : cleaned[..(maxLength - extension.Length)] + extension;
    }

    private static void TryDelete(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
        }
        catch (IOException)
        {
            // A locked file must not fail the delete: the index entry is already gone, so the
            // orphan is invisible and is cleaned with the title's folder when the title goes.
        }
    }

    private static Result<IReadOnlyList<MediaAttachmentDto>> NotFound(Guid mediaId) =>
        Result<IReadOnlyList<MediaAttachmentDto>>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));

    private static Result<IReadOnlyList<MediaAttachmentDto>> Failure(Error error) =>
        Result<IReadOnlyList<MediaAttachmentDto>>.Failure(error);
}
