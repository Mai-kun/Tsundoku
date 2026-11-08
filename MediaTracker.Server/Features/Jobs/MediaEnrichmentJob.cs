using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External;
using MediaTracker.Server.Features.External.GetExternalRelations;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.Rawg;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Storage;

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

            ExternalMediaDto? external;
            try
            {
                external = await services.GetRequiredService<MetadataAggregatorService>()
                    .GetDetailsAsync(
                        AggregatorTypes.Resolve(item),
                        item.ExternalId ?? string.Empty,
                        item.Title,
                        jobCts.Token,
                        item.ExternalSource)
                    .ConfigureAwait(false);
            }
            catch (SourceUnavailableException)
            {
                // The pinned provider is unreachable (down, region-blocked, hard rate-limited): a
                // title-based fan-out still fills the row from the sources that answer, instead of
                // leaving a bare card with no linked sources and a rotting hotlink cover.
                external = await FallbackByTitleAsync(services, item, jobCts.Token).ConfigureAwait(false);
                if (external is null)
                {
                    throw;
                }
            }

            Report(progress, 60, "Скачивание обложки");

            if (await ApplyAsync(db, item, external, services, jobCts.Token).ConfigureAwait(false))
            {
                if (item is TvShow show)
                {
                    foreach (var season in show.Seasons)
                    {
                        await db.InsertTvSeasonAsync(season, jobCts.Token).ConfigureAwait(false);
                    }
                }
                item.MarkUpdated();
                await db.UpdateMediaItemAsync(item, jobCts.Token).ConfigureAwait(false);
            }

            Report(progress, 90, "Сохранение сезонов и глав");

            item.SyncStatus = SyncStatus.Ready;
            item.MarkUpdated();
            await db.UpdateMediaItemAsync(item, jobCts.Token).ConfigureAwait(false);
            MediaListCache.Invalidate();
            AdvancedStatsCalculator.InvalidateCache(services.GetService<Microsoft.Extensions.Caching.Memory.IMemoryCache>());
            TasteProfileCalculator.InvalidateCache(services.GetService<Microsoft.Extensions.Caching.Memory.IMemoryCache>());

            // Last, and outside the metadata write: the Related tab is the one panel whose content is
            // not in the database, so leaving it to the first manual "load related" meant a freshly
            // added title showed an empty tab until the user picked a source by hand.
            await CacheRelatedAsync(services, item, jobCts.Token).ConfigureAwait(false);

            // Same story for a game's achievements: without this the panel stayed at Steam's ten
            // highlighted entries until the user pressed "update metadata" by hand.
            if (item is VideoGame)
            {
                await CacheAchievementsAsync(services, item, external?.SteamAppId, jobCts.Token).ConfigureAwait(false);
                await SyncPlayerAchievementsAsync(services, db, item, jobCts.Token).ConfigureAwait(false);
                await LinkGameFranchiseAsync(services, db, item, jobCts.Token).ConfigureAwait(false);
            }

            await db.UpdateMediaItemAsync(item, jobCts.Token).ConfigureAwait(false);

            Report(progress, 100, "Готово");
        }
        catch
        {
            await MarkFailedAsync(db, item).ConfigureAwait(false);
            throw;
        }
    }

    /// <summary>
    /// Title-based fallback for a row whose pinned provider is unreachable: the aggregator searches
    /// every priority source by the stored titles (romaji and original included) and merges whatever
    /// answers. Only a merge that actually found something is trusted — an all-empty answer would
    /// overwrite the row's data with nulls.
    /// </summary>
    public static async Task<ExternalMediaDto?> FallbackByTitleAsync(
        IServiceProvider services,
        MediaItem item,
        CancellationToken ct)
    {
        var aggregator = services.GetRequiredService<MetadataAggregatorService>();
        string? romaji = item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        };
        var stub = new ExternalMediaDto
        {
            ExternalId = item.ExternalId ?? string.Empty,
            Title = item.Title,
            Type = AggregatorTypes.Resolve(item),
            RomajiTitle = romaji,
            OriginalTitle = item.OriginalTitle,
            ExternalSource = item.ExternalSource,
        };

        var merged = await aggregator.EnrichAsync(stub, AggregatorTypes.Resolve(item), ct).ConfigureAwait(false);
        return merged.SourceContributions is { Count: > 0 } ? merged : null;
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
            await db.UpdateMediaItemAsync(item, CancellationToken.None).ConfigureAwait(false);
            MediaListCache.Invalidate();
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

            item.RelatedMediaJson = JsonSerializer.Serialize(related, AppJsonSerializerContext.Default.IReadOnlyListExternalRelationDto);
            item.RelatedSource = item.ExternalSource;
            item.MarkUpdated();
            await services.GetRequiredService<AppDbContext>()
                .UpdateMediaItemAsync(item, CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // A missing relations endpoint is the normal case for most providers, not an error.
        }
    }

    /// <summary>
    /// Stores the game's full achievement list on the row right after creation, from the same
    /// provider the game was added with (Steam/RAWG). Never overwrites an existing payload and never
    /// fails the job: a provider outage just leaves the panel to its live fetch.
    /// </summary>
    private static async Task CacheAchievementsAsync(
        IServiceProvider services,
        MediaItem item,
        string? steamAppId,
        CancellationToken ct)
    {
        if (item.AchievementsJson is not null || string.IsNullOrWhiteSpace(item.ExternalSource))
        {
            return;
        }

        try
        {
            var isSteam = string.Equals(item.ExternalSource, "steam", StringComparison.OrdinalIgnoreCase);
            var result = await services.GetRequiredService<RawgGameService>()
                .GetAchievementsAsync(
                    isSteam ? item.ExternalId : steamAppId,
                    string.Equals(item.ExternalSource, "rawg", StringComparison.OrdinalIgnoreCase)
                        ? item.ExternalId
                        : null,
                    item.Title,
                    item.ExternalSource,
                    item.ExternalId,
                    ct)
                .ConfigureAwait(false);

            if (result.Achievements.Count == 0)
            {
                return;
            }

            item.AchievementsJson = JsonSerializer.Serialize(new CachedAchievementsPayload(result.TotalCount, result.Achievements), AppJsonSerializerContext.Default.CachedAchievementsPayload);

            item.MarkUpdated();
            await services.GetRequiredService<AppDbContext>()
                .UpdateMediaItemAsync(item, CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Achievements are decoration: the row stays valid without them.
        }
    }

    /// <summary>
    /// The explicit-refresh path for the player's own achievements: when a Steam Web API key and a
    /// SteamID64 are known (the import stores it), the unlocked achievements are re-read and merged,
    /// with an <see cref="MediaEventType.AchievementUnlocked"/> event per name the player gained
    /// since the last sync. Best effort — an unreachable or private profile just skips the step.
    /// </summary>
    private static async Task SyncPlayerAchievementsAsync(
        IServiceProvider services,
        AppDbContext db,
        MediaItem item,
        CancellationToken ct)
    {
        try
        {
            if (!string.Equals(item.ExternalSource, "Steam", StringComparison.OrdinalIgnoreCase)
                || string.IsNullOrWhiteSpace(item.ExternalId))
            {
                return;
            }

            var rawg = services.GetRequiredService<RawgGameService>();
            var steamId = await AppSettingStore.ReadAsync(db, "Steam_SteamId64", ct);
            if (string.IsNullOrWhiteSpace(steamId))
            {
                return;
            }

            var unlocked = await rawg.GetPlayerAchievementsAsync(steamId, item.ExternalId, ct);
            if (unlocked.Count == 0)
            {
                return;
            }

            var merged = MediaAchievements.MergeUnlocked(item.UnlockedAchievements, unlocked);
            if (string.Equals(merged, item.UnlockedAchievements, StringComparison.Ordinal))
            {
                return;
            }

            foreach (var name in MediaAchievements.NewlyUnlocked(item.UnlockedAchievements, merged))
            {
                await db.InsertMediaEventAsync(MediaEventRecorder.AchievementUnlocked(item, name), ct);
            }

            item.UnlockedAchievements = merged;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Player progress is decoration too; the metadata write must survive its failure.
        }
    }

    /// <summary>
    /// RAWG's <c>game-series</c> rows (cached into RelatedMediaJson by <see cref="CacheRelatedAsync"/>)
    /// are franchise evidence for games: titles sharing a series join one franchise with a
    /// chronological order. The FranchiseService does the matching and refuses lone titles.
    /// </summary>
    private static async Task LinkGameFranchiseAsync(
        IServiceProvider services,
        AppDbContext db,
        MediaItem item,
        CancellationToken ct)
    {
        try
        {
            if (item.FranchiseId is not null) return;

            var series = (MediaJsonCache.Deserialize<ExternalRelationDto>(item.RelatedMediaJson) ?? [])
                .Where(r => r.Media is not null
                    && string.Equals(r.Media.Type, "game", StringComparison.OrdinalIgnoreCase)
                    && r.Media.ExternalSource is not null)
                .Select(r => r)
                .ToList();
            if (series.Count == 0) return;

            await services.GetRequiredService<IFranchiseService>()
                .LinkGameSeriesAsync(db, item, series, ct)
                .ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // A missed franchise link is cosmetic; the enrichment must not fail over it.
        }
    }

    private static Task<MediaItem?> LoadAsync(AppDbContext db, Guid mediaId) =>
        db.LoadMediaItemAsync(mediaId);

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

        await MediaMetadataApplier.ApplyOverwriteAsync(
            item,
            external,
            services.GetRequiredService<IImageStorageService>(),
            ct,
            _ => { },
            fillMissing: false).ConfigureAwait(false);

        // Every provider that answered the enrichment joins the linked-sources list, so the card
        // accumulates the full cross-source history instead of only the current primary source.
        LinkedSourceCatalog.AppendFromExternal(
            item, external.ExternalSource, external.ExternalId, external.Title);

        // A second source that actually added data (cast, trailer, genres...) auto-binds as a
        // secondary source together with the honest list of the fields it contributed.
        if (external.SourceContributions is { Count: > 0 } contributions)
        {
            foreach (var contribution in contributions)
            {
                LinkedSourceCatalog.AppendFromExternal(
                    item,
                    contribution.Source,
                    contribution.ExternalId,
                    contribution.Title,
                    [.. contribution.Fields]);
            }
        }

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

/// <summary>The stored shape of <c>AchievementsJson</c>: <c>{"total":N,"items":[...]}</c>.</summary>
public sealed record CachedAchievementsPayload(int Total, IReadOnlyList<GameAchievementItem> Items);
