using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.External.RefreshMetadata;

public sealed record RefreshMetadataCommand(Guid MediaId, bool FillMissingOnly = false);

public interface IRefreshMetadataHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(RefreshMetadataCommand command, CancellationToken ct);
}

public sealed class RefreshMetadataHandler(
    AppDbContext db,
    MetadataAggregatorService metadataAggregator,
    ISourcePriorityService priorityService,
    IImageStorageService imageStorage,
    IMemoryCache cache) : IRefreshMetadataHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(RefreshMetadataCommand command, CancellationToken ct)
    {
        var item = await db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
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
                season => db.Entry(season).State = EntityState.Added);
        }
        else
        {
            await MediaMetadataApplier.ApplyOverwriteAsync(
                item,
                external,
                imageStorage,
                ct,
                season => db.Entry(season).State = EntityState.Added);

            // The user asked for the source to win, so the row is no longer carrying their edits and
            // the next refresh must not prompt them again.
            item.IsCustomEdited = false;
        }

        // A source disabled in settings leaves a stale badge behind otherwise: refresh only rewrites
        // what the queried source reported, so nothing else ever removed one.
        MediaMetadataApplier.RemoveDisabledRatings(
            item,
            await priorityService.GetDisabledSourcesAsync(ct));

        item.MarkUpdated();
        await db.SaveChangesAsync(ct);
        cache.Remove(AdvancedStatsCalculator.CacheKey);

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
