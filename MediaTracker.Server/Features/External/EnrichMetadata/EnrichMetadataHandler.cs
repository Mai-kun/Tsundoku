using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
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

                    var external = await aggregator.GetDetailsAsync(
                        AggregatorTypes.Resolve(current),
                        current.ExternalId ?? string.Empty,
                        current.Title,
                        token,
                        command.Source ?? current.ExternalSource);

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 60, "Обновление обложки и связей", JobStatus.Running, DateTime.MinValue, null));

                    var changed =
                        external is not null
                        && MediaMetadataApplier.ApplyIfMissing(
                            current,
                            external,
                            _ => { });

                    progress.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 90, "Сохранение", JobStatus.Running, DateTime.MinValue, null));

                    current.SyncStatus = SyncStatus.Ready;
                    if (changed)
                    {
                        current.MarkUpdated();
                        AdvancedStatsCalculator.InvalidateCache(cache);
                        TasteProfileCalculator.InvalidateCache(cache);
                    }
                    await scopedDb.UpdateMediaItemAsync(current, token);
                }
                catch (Exception ex)
                {
                    try
                    {
                        current.SyncStatus = SyncStatus.Ready;
                        await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                    }
                    catch
                    {
                    }
                    logger.LogWarning(ex, "Enrichment for media {MediaId} failed", command.MediaId);
                    throw;
                }
            });

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}
