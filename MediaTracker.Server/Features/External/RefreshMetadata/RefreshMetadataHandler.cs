using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.External.RefreshMetadata;

public sealed record RefreshMetadataCommand(Guid MediaId, bool FillMissingOnly = false);

public interface IRefreshMetadataHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(RefreshMetadataCommand command, CancellationToken ct);
}

/// <summary>
/// Refresh: re-reads the source and lets it overwrite the stored values, including the cover.
/// With <c>FillMissingOnly</c> it degrades to the enrich rules instead, which is what the
/// "keep my edits" branch of the dialog calls: the user's own values survive, only gaps are filled.
/// </summary>
public sealed class RefreshMetadataHandler(
    AppDbContext db,
    MetadataAggregatorService metadataAggregator,
    IMetadataProviderResolver providerResolver,
    ISourcePriorityService priorityService,
    IImageStorageService imageStorage) : IRefreshMetadataHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(RefreshMetadataCommand command, CancellationToken ct)
    {
        var item = await db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
            .AsSplitQuery()
            .SingleOrDefaultAsync(media => media.Id == command.MediaId, ct);

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.MediaId}' was not found."));
        }

        var external = await metadataAggregator.GetDetailsAsync(
            AggregatorTypes.Resolve(item),
            item.ExternalId ?? string.Empty,
            item.Title,
            ct,
            item.ExternalSource);

        if (external is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound("Metadata could not be found from external source."));
        }

        if (command.FillMissingOnly)
        {
            // No cover download and no title rewrite: the whole point of this branch is that
            // everything already filled in stays exactly as the user left it.
            MediaMetadataApplier.ApplyIfMissing(
                item,
                external,
                season => db.Entry(season).State = EntityState.Added,
                volume => db.Entry(volume).State = EntityState.Added);
        }
        else
        {
            await MediaMetadataApplier.ApplyOverwriteAsync(
                item,
                external,
                imageStorage,
                ct,
                season => db.Entry(season).State = EntityState.Added,
                volume => db.Entry(volume).State = EntityState.Added);

            // The user asked for the source to win, so the row is no longer carrying their edits and
            // the next refresh must not prompt them again.
            item.IsCustomEdited = false;
        }

        // "Refresh" is the user's explicit "make this match the source", so a manga that was added
        // from a source without a volume breakdown gets its real volumes here too.
        if (item is Manga manga)
        {
            await MangaVolumeStructure.ApplyCanonicalVolumesAsync(
                providerResolver,
                db,
                manga,
                external.VolumeDetails,
                ct);
        }

        // A source disabled in settings leaves a stale badge behind otherwise: refresh only rewrites
        // what the queried source reported, so nothing else ever removed one.
        MediaMetadataApplier.RemoveDisabledRatings(
            item,
            await priorityService.GetDisabledSourcesAsync(ct));

        item.MarkUpdated();
        await db.SaveChangesAsync(ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}

/// <summary>The media type the aggregator should search for, with anime as its own bucket.</summary>
public static class AggregatorTypes
{
    public static string Resolve(MediaItem item) =>
        item is TvShow { IsAnime: true } or Movie { IsAnime: true }
            ? "anime"
            : MediaResponseMapper.GetType(item);
}
