using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.GetExternalRelations;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// The heavy half of adding a title from search: provider lookup, cover download and WebP encode,
/// then the season/volume rows. Split out of <see cref="Media.CreateMedia.CreateMediaHandler"/>
/// so the request can return the draft row the moment it is written.
/// </summary>
public static class MediaEnrichmentJob
{
    /// <summary>
    /// Whole-job budget, generous next to the 8s the synchronous enrich call allowed because
    /// nothing is waiting on a request timeout here.
    /// </summary>
    private static readonly TimeSpan JobTimeout = TimeSpan.FromSeconds(60);

    public static async Task RunAsync(
        IServiceProvider services,
        Guid mediaId,
        CancellationToken ct,
        IProgress<JobProgressDto> progress)
    {
        using var jobCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        jobCts.CancelAfter(JobTimeout);

        var db = services.GetRequiredService<AppDbContext>();

        // Loaded without the job token on purpose: a single-row lookup that always completes is what
        // lets the catch below mark the item even when the cancellation landed on this very call.
        var item = await LoadAsync(db, mediaId).ConfigureAwait(false);

        if (item is null)
        {
            return;
        }

        try
        {
            Report(progress, 20, "Поиск метаданных");

            var external = await services.GetRequiredService<MetadataAggregatorService>()
                .GetDetailsAsync(
                    AggregatorTypes.Resolve(item),
                    item.ExternalId ?? string.Empty,
                    item.Title,
                    jobCts.Token,
                    item.ExternalSource)
                .ConfigureAwait(false);

            Report(progress, 60, "Скачивание обложки");

            if (await ApplyAsync(db, item, external, services, jobCts.Token).ConfigureAwait(false))
            {
                item.MarkUpdated();
                await db.SaveChangesAsync(jobCts.Token).ConfigureAwait(false);
            }

            Report(progress, 90, "Сохранение сезонов и глав");

            item.SyncStatus = SyncStatus.Ready;
            item.MarkUpdated();
            await db.SaveChangesAsync(jobCts.Token).ConfigureAwait(false);

            // Last, and outside the metadata write: the Related tab is the one panel whose content is
            // not in the database, so leaving it to the first manual "load related" meant a freshly
            // added title showed an empty tab until the user picked a source by hand.
            await CacheRelatedAsync(services, item, jobCts.Token).ConfigureAwait(false);

            Report(progress, 100, "Готово");
        }
        catch
        {
            await MarkFailedAsync(db, item).ConfigureAwait(false);
            throw;
        }
    }

    /// <summary>
    /// Best effort: the point is only to stop the card spinning forever, so a failure to record it
    /// (a context already disposed on shutdown) must not mask the error that got us here.
    /// </summary>
    private static async Task MarkFailedAsync(AppDbContext db, MediaItem item)
    {
        try
        {
            item.SyncStatus = SyncStatus.Failed;
            item.MarkUpdated();
            await db.SaveChangesAsync(CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
        }
    }

    /// <summary>
    /// Fills the Related cache from whatever source the item already points at. Never overwrites an
    /// existing cache and never fails the job: a provider without a relations endpoint simply returns
    /// an empty list, and the tab then loads on demand exactly as it did before.
    /// </summary>
    private static async Task CacheRelatedAsync(
        IServiceProvider services,
        MediaItem item,
        CancellationToken ct)
    {
        if (item.RelatedMediaJson is not null || string.IsNullOrWhiteSpace(item.ExternalSource))
        {
            return;
        }

        try
        {
            var result = await services.GetRequiredService<IGetExternalRelationsHandler>()
                .HandleAsync(
                    new GetExternalRelationsQuery(
                        AggregatorTypes.Resolve(item),
                        item.ExternalId,
                        item.Title,
                        item.ExternalSource,
                        "related"),
                    ct)
                .ConfigureAwait(false);

            if (!result.TryGetValue(out var related) || related.Count == 0)
            {
                return;
            }

            item.RelatedMediaJson = JsonSerializer.Serialize(related);
            item.RelatedSource = item.ExternalSource;
            item.MarkUpdated();
            await services.GetRequiredService<AppDbContext>()
                .SaveChangesAsync(CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // A missing relations endpoint is the normal case for most providers, not an error.
        }
    }

    private static Task<MediaItem?> LoadAsync(AppDbContext db, Guid mediaId) =>
        db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
            .AsSplitQuery()
            .SingleOrDefaultAsync(media => media.Id == mediaId);

    /// <summary>
    /// Overwrites the display fields from the provider and swaps the remote cover for a local WebP.
    /// Returns false when the provider gave nothing, which skips the write entirely.
    /// </summary>
    private static async Task<bool> ApplyAsync(
        AppDbContext db,
        MediaItem item,
        ExternalMediaDto? external,
        IServiceProvider services,
        CancellationToken ct)
    {
        if (external is null)
        {
            return false;
        }

        // The applier has no context, so the seam for marking a brand-new season or volume as Added
        // comes from the caller: EF would otherwise save it as an UPDATE against a row that was never
        // inserted.
        await MediaMetadataApplier.ApplyOverwriteAsync(
            item,
            external,
            services.GetRequiredService<IImageStorageService>(),
            ct,
            season => db.Entry(season).State = EntityState.Added,
            volume => db.Entry(volume).State = EntityState.Added).ConfigureAwait(false);

        return true;
    }

    /// <summary>JobId/Title are re-stamped by the worker, which owns the job identity.</summary>
    private static void Report(IProgress<JobProgressDto> progress, int percent, string step) =>
        progress.Report(new JobProgressDto(
            Guid.Empty,
            null,
            string.Empty,
            percent,
            step,
            JobStatus.Running,
            DateTime.MinValue,
            null));
}