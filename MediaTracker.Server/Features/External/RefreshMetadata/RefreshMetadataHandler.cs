using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.External.RefreshMetadata;

/// <summary>
/// <c>UpdateMainCover</c> is only true for an explicit re-point of the primary source: a routine
/// metadata refresh appends the source's cover to the gallery but keeps the poster the user picked.
/// </summary>
public sealed record RefreshMetadataCommand(
    Guid MediaId,
    bool FillMissingOnly = false,
    bool UpdateMainCover = false);

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
        var item = await db.LoadMediaItemAsync(command.MediaId, ct);

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.MediaId}' was not found."));
        }

        item.SyncStatus = SyncStatus.Syncing;
        await db.UpdateMediaItemAsync(item, ct);

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

                var current = await scopedDb.LoadMediaItemAsync(command.MediaId, token);

                if (current is null) return;

                try
                {
                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 20, "Поиск метаданных", JobStatus.Running, DateTime.MinValue, null));

                    var linkedSources = LinkedSourceCatalog.GetFor(current);
                    var primary = linkedSources.FirstOrDefault(source => source.IsPrimary);
                    var source = !string.IsNullOrWhiteSpace(primary?.Source)
                        ? primary.Source
                        : current.ExternalSource;
                    var externalId = primary is not null
                        ? primary.ExternalId
                        : current.ExternalId;
                    var altTitles = MediaMetadataApplier.DeserializeAltTitles(current.AltTitles);

                    ExternalMediaDto? external;
                    try
                    {
                        external = await ExternalApiRetry.RunAsync(
                            async retryToken => await metadataAggregator.GetDetailsAsync(
                                AggregatorTypes.Resolve(current),
                                externalId ?? string.Empty,
                                current.Title,
                                retryToken,
                                source,
                                linkedSources,
                                altTitles,
                                TimeSpan.FromSeconds(50),
                                sources => progress.Report(new JobProgressDto(
                                    Guid.Empty, null, string.Empty, 30,
                                    $"Обогащение: {string.Join(", ", sources)}...",
                                    JobStatus.Running, DateTime.MinValue, null))),
                            sp.GetService<RateLimitTracker>(),
                            source ?? string.Empty,
                            token,
                            seconds =>
                            {
                                progress.Report(new JobProgressDto(
                                    Guid.Empty, null, string.Empty, 20,
                                    $"Ожидание лимита API (повтор через {seconds} сек)...",
                                    JobStatus.Running, DateTime.MinValue, null));
                                return Task.CompletedTask;
                            });
                    }
                    catch (SourceUnavailableException)
                    {
                        // The pinned provider is unreachable: a title-based fan-out across the other
                        // sources still refreshes what it can, instead of failing the whole job and
                        // leaving the card with no data and a dead hotlink cover.
                        external = await MediaEnrichmentJob.FallbackByTitleAsync(sp, current, token);
                        if (external is null)
                        {
                            throw;
                        }
                    }

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
                            _ => { });
                    }
                    else
                    {
                        await MediaMetadataApplier.ApplyOverwriteAsync(
                            current,
                            external,
                            imageStorage,
                            token,
                            _ => { },
                            fillMissing: false,
                            updateMainCover: command.UpdateMainCover);

                        current.IsCustomEdited = false;
                    }

                    // A source that contributed data during this refresh auto-binds as a secondary
                    // source, same as it does on the first-add enrichment job.
                    if (external.SourceContributions is { Count: > 0 } contributions)
                    {
                        foreach (var contribution in contributions)
                        {
                            LinkedSourceCatalog.AppendFromExternal(
                                current,
                                contribution.Source,
                                contribution.ExternalId,
                                contribution.Title,
                                [.. contribution.Fields]);
                        }
                    }

                    if (current is TvShow show)
                    {
                        foreach (var season in show.Seasons)
                        {
                            await scopedDb.InsertTvSeasonAsync(season, token);
                        }
                    }

                    MediaMetadataApplier.RemoveDisabledRatings(
                        current,
                        await priorityService.GetDisabledSourcesAsync(token));

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 90, "Сохранение", JobStatus.Running, DateTime.MinValue, null));

                    var finalSources = LinkedSourceCatalog.GetFor(current);
                    LinkedSourceCatalog.SaveFor(current, finalSources);

                    current.SyncStatus = SyncStatus.Ready;
                    current.MarkUpdated();
                    await scopedDb.UpdateMediaItemAsync(current, token);
                    MediaListCache.Invalidate();
                    AdvancedStatsCalculator.InvalidateCache(cache);
                    TasteProfileCalculator.InvalidateCache(cache);
                }
                catch
                {
                    try
                    {
                        current.SyncStatus = SyncStatus.Failed;
                        current.MarkUpdated();
                        await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                        MediaListCache.Invalidate();
                    }
                    catch
                    {
                    }
                    throw;
                }
            },
            highPriority: true,
            initialStep: "В очереди на обновление...");

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
