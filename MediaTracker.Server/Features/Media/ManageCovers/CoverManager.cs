using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Features.Media.ManageCovers;

public sealed record AddCoverByUrlCommand(Guid MediaId, string Url, string? Source, bool SetAsActive);

public sealed record AddCoverFileCommand(Guid MediaId, Stream Content, string? Source, bool SetAsActive);

public sealed record SelectCoverCommand(Guid MediaId, string CoverId);

public sealed record DeleteCoverCommand(Guid MediaId, string CoverId);

public interface ICoverManager
{
    Task<Result<MediaDetailDto>> AddByUrlAsync(AddCoverByUrlCommand command, CancellationToken ct);

    Task<Result<MediaDetailDto>> AddFromFileAsync(AddCoverFileCommand command, CancellationToken ct);

    Task<Result<MediaDetailDto>> SelectAsync(SelectCoverCommand command, CancellationToken ct);

    Task<Result<MediaDetailDto>> DeleteAsync(DeleteCoverCommand command, CancellationToken ct);
}

/// <summary>
/// The cover gallery's write side: add a variant (by URL or upload), make one active, delete one.
/// Everything goes through <see cref="MediaCoverCollection"/>, so a row written before the gallery
/// existed gets its current poster registered as entry #1 the first time any of these runs.
/// </summary>
public sealed class CoverManager(AppDbContext db, IImageStorageService imageStorage) : ICoverManager
{
    public async Task<Result<MediaDetailDto>> AddByUrlAsync(AddCoverByUrlCommand command, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(command.Url))
        {
            return Result<MediaDetailDto>.Failure(Error.Validation("Cover URL must not be empty."));
        }

        return await AddVariantAsync(
            command.MediaId,
            () => imageStorage.SaveCoverVariantAsync(command.Url, command.MediaId, command.Source, ct),
            command.SetAsActive,
            ct);
    }

    public async Task<Result<MediaDetailDto>> AddFromFileAsync(AddCoverFileCommand command, CancellationToken ct) =>
        await AddVariantAsync(
            command.MediaId,
            () => imageStorage.SaveCoverVariantAsync(command.Content, command.MediaId, command.Source, ct),
            command.SetAsActive,
            ct);

    public async Task<Result<MediaDetailDto>> SelectAsync(SelectCoverCommand command, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(command.MediaId, ct);
        if (item is null)
        {
            return NotFound(command.MediaId);
        }

        var covers = MediaCoverCollection.Parse(item.CoversJson);
        var chosen = covers.Find(cover => cover.Id == command.CoverId);
        if (chosen is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Cover variant '{command.CoverId}' was not found on media item '{command.MediaId}'."));
        }

        item.CoverUrl = chosen.ThumbUrl;
        item.IsCustomEdited = true;
        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item, ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    public async Task<Result<MediaDetailDto>> DeleteAsync(DeleteCoverCommand command, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(command.MediaId, ct);
        if (item is null)
        {
            return NotFound(command.MediaId);
        }

        var covers = MediaCoverCollection.Parse(item.CoversJson);
        var removed = covers.Find(cover => cover.Id == command.CoverId);
        if (removed is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Cover variant '{command.CoverId}' was not found on media item '{command.MediaId}'."));
        }

        covers.Remove(removed);
        item.CoversJson = MediaCoverCollection.Serialize(covers);
        DeleteCoverFiles(item, removed);

        // The active poster must never dangle: fall through to the next variant, or to none at all
        // when the gallery just went empty.
        if (item.CoverUrl is { } active
            && (active.Split('?')[0].Equals(removed.ThumbUrl, StringComparison.OrdinalIgnoreCase)
                || covers.Count == 0))
        {
            item.CoverUrl = covers.Count > 0 ? covers[^1].ThumbUrl : null;
        }

        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item, ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    private async Task<Result<MediaDetailDto>> AddVariantAsync(
        Guid mediaId,
        Func<Task<MediaCoverItemDto?>> download,
        bool setAsActive,
        CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(mediaId, ct);
        if (item is null)
        {
            return NotFound(mediaId);
        }

        MediaCoverCollection.EnsureLegacyCoverRegistered(item);

        var variant = await download();
        if (variant is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.Validation("The cover could not be downloaded or decoded. Check the URL and the image size (10 MB max)."));
        }

        var covers = MediaCoverCollection.Parse(item.CoversJson);
        covers.Add(variant);
        item.CoversJson = MediaCoverCollection.Serialize(covers);

        if (setAsActive)
        {
            item.CoverUrl = variant.ThumbUrl;
            item.IsCustomEdited = true;
        }

        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item, ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    private void DeleteCoverFiles(Domain.Entities.MediaItem item, MediaCoverItemDto removed)
    {
        // The pre-gallery entry has no per-variant folder; its two files live in the shared "cover"
        // folder and are removed by URL, exactly the way the old single-cover delete worked.
        if (removed.Id == MediaCoverCollection.LegacyCoverId)
        {
            imageStorage.DeleteCover(removed.ThumbUrl);
            imageStorage.DeleteCover(removed.OriginalUrl);
            return;
        }

        imageStorage.DeleteCoverVariant(item.Id, removed.Id);
    }

    private static Result<MediaDetailDto> NotFound(Guid mediaId) =>
        Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{mediaId}' was not found."));
}
