using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.External.EnrichMetadata;

public sealed record EnrichMetadataCommand(Guid MediaId);

public interface IEnrichMetadataHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(EnrichMetadataCommand command, CancellationToken ct);
}

/// <summary>
/// Background quality pass: an unreachable or slow provider must not fail the request, the user still
/// gets the item they asked for.
/// </summary>
public sealed class EnrichMetadataHandler(
    AppDbContext db,
    MetadataAggregatorService aggregator,
    IMetadataProviderResolver providerResolver,
    ILogger<EnrichMetadataHandler> logger) : IEnrichMetadataHandler
{
    private static readonly TimeSpan EnrichmentTimeout = TimeSpan.FromSeconds(8);

    public async Task<Result<MediaDetailDto>> HandleAsync(EnrichMetadataCommand command, CancellationToken ct)
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

        try
        {
            using var enrichCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            enrichCts.CancelAfter(EnrichmentTimeout);

            var external = await aggregator.GetDetailsAsync(
                AggregatorTypes.Resolve(item),
                item.ExternalId ?? string.Empty,
                item.Title,
                enrichCts.Token,
                item.ExternalSource);

            // Missing metadata is a gap fill, not an error: the detail payload is returned either way.
            var changed =
                external is not null
                && MediaMetadataApplier.ApplyIfMissing(
                    item,
                    external,
                    season => db.Entry(season).State = EntityState.Added,
                    volume => db.Entry(volume).State = EntityState.Added);

            // Sources without a volume breakdown (Shikimori) never fill the per-volume chapter counts,
            // so the library would keep the even placeholder split. Ask MangaDex by title as a
            // background second opinion and let it replace the made-up numbers with the real ones.
            if (item is Manga manga
                && external?.VolumeDetails is not { Count: > 0 }
                && NeedsRealVolumes(manga))
            {
                changed |= await ApplyMangaDexVolumesAsync(manga, enrichCts.Token);
            }

            if (changed)
            {
                item.MarkUpdated();
                await db.SaveChangesAsync(ct);
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

    /// <summary>
    /// A volume still carrying the even split the placeholder seeder invented is not real data, so it
    /// is worth one background lookup. Volumes the user typed keep their own count and are left alone.
    /// </summary>
    private static bool NeedsRealVolumes(Manga manga) =>
        manga.Volumes.Count > 0
        && manga.Volumes.Any(volume =>
            volume.CurrentChapter == 0
            && (volume.TotalChapters == 0
                || volume.TotalChapters == Manga.SeededChaptersPerVolume(manga.TotalChapters, manga.Volumes.Count)));

    private async Task<bool> ApplyMangaDexVolumesAsync(Manga manga, CancellationToken ct)
    {
        if (providerResolver.Resolve("manga", MangaDexMetadataProvider.Source.Id) is not MangaDexMetadataProvider mangadex)
        {
            return false;
        }

        var details = await mangadex.GetVolumeDetailsByTitleAsync(manga.Title, ct);
        if (details.Count == 0) return false;

        var volumesBefore = manga.Volumes.Count;
        MediaMetadataApplier.ApplyRealVolumes(
            manga,
            details,
            volume => db.Entry(volume).State = EntityState.Added);

        return manga.Volumes.Count != volumesBefore;
    }
}
