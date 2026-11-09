using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.External.EnrichMetadata;

public sealed record EnrichMetadataCommand(Guid MediaId, string? Source = null);

public interface IEnrichMetadataHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(EnrichMetadataCommand command, CancellationToken ct);
}

public sealed class EnrichMetadataHandler(
    AppDbContext db,
    IJobManager jobs,
    ILogger<EnrichMetadataHandler> logger) : IEnrichMetadataHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(EnrichMetadataCommand command, CancellationToken ct)
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
                var aggregator = sp.GetRequiredService<MetadataAggregatorService>();
                var cache = sp.GetRequiredService<IMemoryCache>();

                var current = await scopedDb.LoadMediaItemAsync(command.MediaId, token);

                if (current is null) return;

                try
                {
                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 20, "Поиск метаданных", JobStatus.Running, DateTime.MinValue, null));

                    var linkedSources = LinkedSourceCatalog.GetFor(current);
                    var primary = linkedSources.FirstOrDefault(source => source.IsPrimary);
                    var requestedSource = command.Source ?? primary?.Source ?? current.ExternalSource;
                    var requestedRow = linkedSources
                        .FirstOrDefault(source => MediaMerger.NormalizeSourceKey(source.Source)
                            == MediaMerger.NormalizeSourceKey(requestedSource ?? string.Empty));
                    var requestedId = requestedRow?.ExternalId;
                    // The root id only belongs to the root source: reusing it for a source that has
                    // no id yet would ask that provider for another provider's record.
                    if (string.IsNullOrWhiteSpace(requestedId)
                        && requestedRow is null
                        && MediaMerger.NormalizeSourceKey(requestedSource ?? string.Empty)
                            == MediaMerger.NormalizeSourceKey(current.ExternalSource ?? string.Empty))
                    {
                        requestedId = current.ExternalId;
                    }

                    var altTitles = MediaMetadataApplier.DeserializeAltTitles(current.AltTitles);
                    var external = await ExternalApiRetry.RunAsync(
                        async retryToken => await aggregator.GetDetailsAsync(
                            AggregatorTypes.Resolve(current),
                            requestedId ?? string.Empty,
                            current.Title,
                            retryToken,
                            requestedSource,
                            linkedSources,
                            altTitles,
                            TimeSpan.FromSeconds(50),
                            sources => progress.Report(new JobProgressDto(
                                Guid.Empty, null, string.Empty, 30,
                                $"Обогащение: {string.Join(", ", sources)}...",
                                JobStatus.Running, DateTime.MinValue, null))),
                        sp.GetService<RateLimitTracker>(),
                        requestedSource ?? string.Empty,
                        token,
                        seconds =>
                        {
                            progress.Report(new JobProgressDto(
                                Guid.Empty, null, string.Empty, 20,
                                $"Ожидание лимита API (повтор через {seconds} сек)...",
                                JobStatus.Running, DateTime.MinValue, null));
                            return Task.CompletedTask;
                        });

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 60, "Обновление обложки и связей", JobStatus.Running, DateTime.MinValue, null));

                    var changed =
                        external is not null
                        && MediaMetadataApplier.ApplyIfMissing(
                            current,
                            external,
                            _ => { });

                    // A source that contributed data (even only a rating) auto-binds, the same way
                    // the refresh and add jobs do; without this the panel lost the contributor.
                    if (external?.SourceContributions is { Count: > 0 } contributions)
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

                        changed = true;
                    }

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 90, "Сохранение", JobStatus.Running, DateTime.MinValue, null));

                    current.SyncStatus = SyncStatus.Ready;
                    if (changed)
                    {
                        if (current is TvShow show)
                        {
                            foreach (var season in show.Seasons)
                            {
                                await scopedDb.InsertTvSeasonAsync(season, token);
                            }
                        }
                        current.MarkUpdated();
                        AdvancedStatsCalculator.InvalidateCache(cache);
                        TasteProfileCalculator.InvalidateCache(cache);
                    }
                    await scopedDb.UpdateMediaItemAsync(current, token);
                    MediaListCache.Invalidate();
                }
                catch (Exception ex)
                {
                    try
                    {
                        current.SyncStatus = SyncStatus.Ready;
                        await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                        MediaListCache.Invalidate();
                    }
                    catch
                    {
                    }
                    logger.LogWarning(ex, "Enrichment for media {MediaId} failed", command.MediaId);
                    throw;
                }
            },
            highPriority: true,
            initialStep: "В очереди на обновление...");

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}
