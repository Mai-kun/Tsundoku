using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// What one auto-refresh poll did to the item: whether the API was reachable (false means the check
/// was silently deferred by a day) and whether new content came out of it.
/// </summary>
public sealed record AutoRefreshOutcome(bool Ok, bool HasNewContent);

/// <summary>
/// The one per-title poll both the background worker and the calendar's manual trigger share, so the
/// two can never drift apart on what counts as new content or how the schedule moves.
/// </summary>
public static class AutoRefreshRunner
{
    public static async Task<AutoRefreshOutcome> RunAsync(
        AppDbContext db,
        MetadataAggregatorService aggregator,
        ILogger logger,
        MediaItem item,
        CancellationToken ct)
    {
        const string logTag = "[AutoRefresh]";

        var oldChapters = item is Manga manga ? manga.TotalChapters : null;
        var oldVolumes = item is Manga manga2 ? manga2.TotalVolumes : null;
        var oldEpisodes = item is TvShow show ? show.TotalEpisodesCount : 0;
        var oldSeasons = item is TvShow show2 ? show2.Seasons.Count : 0;
        var wasFinished = string.Equals(item.ReleaseStatus, ReleaseStatusRules.Finished, StringComparison.OrdinalIgnoreCase);

        ExternalMediaDto? external;
        try
        {
            external = await aggregator.GetDetailsAsync(
                AggregatorTypes.Resolve(item),
                item.ExternalId ?? string.Empty,
                item.Title,
                ct,
                item.ExternalSource);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return await DeferAsync(db, logger, item, ex, ct);
        }

        if (external is null)
        {
            return await DeferAsync(db, logger, item, null, ct);
        }

        // Counted before the applier touches the row: the growth decision belongs to the old state.
        var newChapters = external.Chapters ?? external.TotalCount;
        var newVolumes = external.Volumes;
        var newEpisodes = external.TotalCount ?? external.Seasons?.Sum(season => season.TotalEpisodes) ?? external.Episodes?.Count ?? 0;
        var newSeasons = external.Seasons?.Count ?? 0;
        var hasNewContent =
            external.ReleaseStatus?.ToUpperInvariant() == ReleaseStatusRules.Finished && !wasFinished;

        switch (item)
        {
            case Manga:
                hasNewContent |= newChapters is > 0 && oldChapters is int chapters && newChapters > chapters;
                hasNewContent |= newVolumes is > 0 && oldVolumes is int volumes && newVolumes > volumes;
                break;
            case TvShow:
                hasNewContent |= newEpisodes > 0 && newEpisodes > oldEpisodes;
                hasNewContent |= newSeasons > 0 && newSeasons > oldSeasons;
                break;
        }

        // Safe merge: never wipes a field the user typed, only fills what the row still lacks.
        MediaMetadataApplier.ApplyIfMissing(item, external, _ => { });

        if (hasNewContent)
        {
            if (item is Manga && newChapters is > 0 && oldChapters is int chapters && newChapters > chapters)
            {
                await db.InsertMediaEventAsync(MediaEventRecorder.ProgressChanged(item, $"{chapters} гл.", $"{newChapters} гл."), ct);
            }

            if (item is TvShow && newEpisodes > 0 && newEpisodes > oldEpisodes)
            {
                await db.InsertMediaEventAsync(MediaEventRecorder.ProgressChanged(item, $"{oldEpisodes} эп.", $"{newEpisodes} эп."), ct);
            }

            logger.LogInformation(logTag + " New content detected for '{Title}'!", item.Title);
        }

        AutoRefreshRules.ApplyRefreshSchedule(item, hasNewContent, DateTime.UtcNow);
        item.MarkUpdated();

        if (item is TvShow tvShowItem)
        {
            foreach (var season in tvShowItem.Seasons)
            {
                await db.InsertTvSeasonAsync(season, ct);
            }
        }

        await db.UpdateMediaItemAsync(item, ct);

        return new AutoRefreshOutcome(true, hasNewContent);
    }

    /// <summary>Pushes the check a day out without touching the interval progression.</summary>
    private static async Task<AutoRefreshOutcome> DeferAsync(
        AppDbContext db,
        ILogger logger,
        MediaItem item,
        Exception? cause,
        CancellationToken ct)
    {
        if (cause is not null)
        {
            logger.LogWarning(cause, "[AutoRefresh] '{Title}' source is unavailable; retrying in a day", item.Title);
        }

        item.NextAutoRefreshAt = DateTime.UtcNow.AddDays(1);
        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item, ct);
        return new AutoRefreshOutcome(false, false);
    }
}
