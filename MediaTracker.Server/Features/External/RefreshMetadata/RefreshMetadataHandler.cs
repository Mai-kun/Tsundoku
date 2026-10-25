using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Jobs;
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
    IJobManager jobs) : IRefreshMetadataHandler
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

        item.SyncStatus = SyncStatus.Syncing;
        await db.SaveChangesAsync(ct);

        jobs.Enqueue(
            item.Id,
            item.Title,
            async (sp, token, progress) =>
            {
                var scopedDb = sp.GetRequiredService<AppDbContext>();
                var metadataAggregator = sp.GetRequiredService<MetadataAggregatorService>();
                var priorityService = sp.GetRequiredService<ISourcePriorityService>();
                var imageStorage = sp.GetRequiredService<IImageStorageService>();
                var cache = sp.GetRequiredService<IMemoryCache>();

                var current = await scopedDb.MediaItems
                    .Include(media => media.Franchise)
                    .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
                    .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
                    .AsSplitQuery()
                    .SingleOrDefaultAsync(media => media.Id == command.MediaId, token);

                if (current is null) return;

                try
                {
                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 20, "Поиск метаданных", JobStatus.Running, DateTime.MinValue, null));

                    var external = await metadataAggregator.GetDetailsAsync(
                        AggregatorTypes.Resolve(current),
                        current.ExternalId ?? string.Empty,
                        current.Title,
                        token,
                        current.ExternalSource);

                    if (external is null)
                    {
                        throw new InvalidOperationException("Metadata could not be found from external source.");
                    }

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 60, "Обновление обложки и связей", JobStatus.Running, DateTime.MinValue, null));

                    if (command.FillMissingOnly)
                    {
                        MediaMetadataApplier.ApplyIfMissing(
                            current,
                            external,
                            season => scopedDb.Entry(season).State = EntityState.Added);
                    }
                    else
                    {
                        await MediaMetadataApplier.ApplyOverwriteAsync(
                            current,
                            external,
                            imageStorage,
                            token,
                            season => scopedDb.Entry(season).State = EntityState.Added);

                        current.IsCustomEdited = false;
                    }

                    MediaMetadataApplier.RemoveDisabledRatings(
                        current,
                        await priorityService.GetDisabledSourcesAsync(token));

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 90, "Сохранение", JobStatus.Running, DateTime.MinValue, null));

                    current.SyncStatus = SyncStatus.Ready;
                    current.MarkUpdated();
                    await scopedDb.SaveChangesAsync(token);
                    AdvancedStatsCalculator.InvalidateCache(cache);
                    TasteProfileCalculator.InvalidateCache(cache);
                }
                catch
                {
                    try
                    {
                        current.SyncStatus = SyncStatus.Failed;
                        current.MarkUpdated();
                        await scopedDb.SaveChangesAsync(CancellationToken.None);
                    }
                    catch
                    {
                    }
                    throw;
                }
            });

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
