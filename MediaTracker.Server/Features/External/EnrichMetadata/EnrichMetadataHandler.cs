using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
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
    MetadataAggregatorService aggregator,
    ILogger<EnrichMetadataHandler> logger,
    IMemoryCache cache) : IEnrichMetadataHandler
{
    private static readonly TimeSpan EnrichmentTimeout = TimeSpan.FromSeconds(8);

    public async Task<Result<MediaDetailDto>> HandleAsync(EnrichMetadataCommand command, CancellationToken ct)
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

        try
        {
            using var enrichCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            enrichCts.CancelAfter(EnrichmentTimeout);

            var external = await aggregator.GetDetailsAsync(
                AggregatorTypes.Resolve(item),
                item.ExternalId ?? string.Empty,
                item.Title,
                enrichCts.Token,
                // "Дополнить" lets the user name a different provider than the row came from, so an
                // empty field can be filled from e.g. TMDb when the item was matched on Kinopoisk.
                command.Source ?? item.ExternalSource);

            // Missing metadata is a gap fill, not an error: the detail payload is returned either way.
            var changed =
                external is not null
                && MediaMetadataApplier.ApplyIfMissing(
                    item,
                    external,
                    season => db.Entry(season).State = EntityState.Added);

            if (changed)
            {
                item.MarkUpdated();
                await db.SaveChangesAsync(ct);
                cache.Remove(AdvancedStatsCalculator.CacheKey);
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning(
                "Enrichment for media {MediaId} timed out after {Timeout}",
                command.MediaId,
                EnrichmentTimeout);
        }
        catch (Exception ex)
        {
            logger.LogWarning(
                ex,
                "Enrichment for media {MediaId} failed, returning the item unchanged",
                command.MediaId);
        }

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}
