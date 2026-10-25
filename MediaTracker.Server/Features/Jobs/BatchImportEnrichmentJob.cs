using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// Enriches a whole import batch sequentially. One job per import instead of one per title keeps the
/// job list readable and makes a single rate-limit-friendly throttle possible: every provider call
/// below is separated from the next title by a fixed pause, so a 500-entry MangaLib export cannot
/// fire 1500 bursts into AniList within a minute and get the key banned.
/// </summary>
public static class BatchImportEnrichmentJob
{
    /// <summary>Pause between titles; external providers rate-limit hard on import-sized traffic.</summary>
    private static readonly TimeSpan Throttle = TimeSpan.FromMilliseconds(2500);

    public static async Task RunAsync(
        IServiceProvider services,
        IReadOnlyList<Guid> mediaIds,
        CancellationToken ct,
        IProgress<JobProgressDto> progress)
    {
        if (mediaIds.Count == 0)
        {
            return;
        }

        var db = services.GetRequiredService<AppDbContext>();
        var aggregator = services.GetRequiredService<MetadataAggregatorService>();
        var imageStorage = services.GetRequiredService<IImageStorageService>();

        int processed = 0, autoCount = 0, reviewCount = 0;

        try
        {
            foreach (var mediaId in mediaIds)
            {
                ct.ThrowIfCancellationRequested();

                if (processed > 0)
                {
                    await Task.Delay(Throttle, ct);
                }

                var item = await LoadAsync(db, mediaId, ct);
                processed++;

                if (item is null)
                {
                    continue;
                }

                progress.Report(new JobProgressDto(
                    Guid.Empty,
                    item.Id,
                    item.Title,
                    processed * 100 / mediaIds.Count,
                    $"[{processed}/{mediaIds.Count}] {item.Title} (авто: {autoCount}, спорных: {reviewCount})",
                    JobStatus.Running,
                    DateTime.MinValue,
                    null));

                try
                {
                    var verdict = await EnrichOneAsync(services, db, aggregator, imageStorage, item, ct);
                    if (verdict == MatchVerdictKind.Confident) autoCount++;
                    else if (verdict == MatchVerdictKind.Ambiguous) reviewCount++;
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception error)
                {
                    // One broken title must not sink the batch: mark it and keep draining.
                    item.SyncStatus = SyncStatus.Failed;
                    item.MarkUpdated();
                    await db.SaveChangesAsync(CancellationToken.None);
                    services.GetRequiredService<ILoggerFactory>()
                        .CreateLogger("BatchImportEnrichmentJob")
                        .LogWarning(error, "[BatchImportEnrichment] '{Title}' failed: {Message}", item.Title, error.Message);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // The queue cancelled us (user or shutdown). Anything still parked in Syncing would spin
            // forever otherwise, so every not-yet-processed row goes back to a calm Ready. The reset
            // runs as a direct UPDATE on a fresh scope with an always-alive token: the tracked-entity
            // SaveChanges path was unreliable once cancellation had already poisoned the context.
            try
            {
                using var cleanupScope = services.CreateScope();
                var cleanupDb = cleanupScope.ServiceProvider.GetRequiredService<AppDbContext>();
                await cleanupDb.MediaItems
                    .Where(m => mediaIds.Contains(m.Id) && m.SyncStatus == SyncStatus.Syncing)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(m => m.SyncStatus, SyncStatus.Ready)
                        .SetProperty(m => m.UpdatedAt, DateTime.UtcNow), CancellationToken.None);
            }
            catch (Exception cleanupError)
            {
                services.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("BatchImportEnrichmentJob")
                    .LogWarning(cleanupError, "Не удалось сбросить SyncStatus при отмене задачи");
            }
            throw;
        }

        progress.Report(new JobProgressDto(
            Guid.Empty,
            null,
            string.Empty,
            100,
            $"Готово (авто: {autoCount}, спорных: {reviewCount})",
            JobStatus.Running,
            DateTime.MinValue,
            null));

        EvictStatsCaches(services);
    }

    private static async Task<MatchVerdictKind> EnrichOneAsync(
        IServiceProvider services,
        AppDbContext db,
        MetadataAggregatorService aggregator,
        IImageStorageService imageStorage,
        MediaItem item,
        CancellationToken ct)
    {
        var type = AggregatorTypes.Resolve(item);
        var candidates = await FindCandidatesAsync(aggregator, item, type, ct);
        var priorities = await services.GetRequiredService<ISourcePriorityService>().GetPrioritiesAsync(type, ct);
        var verdict = ImportMatchScorer.EvaluateCandidates(item, candidates, priorities);

        switch (verdict.Kind)
        {
            case MatchVerdictKind.Confident when await ApplyWinnerAsync(services, db, aggregator, imageStorage, item, verdict.Winner!, type, ct):
                return MatchVerdictKind.Confident;

            case MatchVerdictKind.Confident:
                // The winner vanished between search and details: better to show the candidates than
                // to leave an unfilled row that looks matched.
                item.PendingMatchesJson = MediaJsonCache.Serialize(candidates);
                item.SyncStatus = SyncStatus.NeedsReview;
                break;

            case MatchVerdictKind.Ambiguous:
                item.PendingMatchesJson = MediaJsonCache.Serialize(verdict.Candidates);
                item.SyncStatus = SyncStatus.NeedsReview;
                break;

            case MatchVerdictKind.NoMatch:
            default:
                // Empty candidates list is a verdict too: the user sees "no automatic match found",
                // and the same review screen offers picking a source by hand or leaving the row.
                item.PendingMatchesJson = "[]";
                item.SyncStatus = SyncStatus.NeedsReview;
                break;
        }

        item.MarkUpdated();
        await db.SaveChangesAsync(ct);
        return verdict is { Kind: MatchVerdictKind.Ambiguous } ? MatchVerdictKind.Ambiguous : MatchVerdictKind.NoMatch;
    }

    private static async Task<bool> ApplyWinnerAsync(
        IServiceProvider services,
        AppDbContext db,
        MetadataAggregatorService aggregator,
        IImageStorageService imageStorage,
        MediaItem item,
        ExternalMediaDto winner,
        string type,
        CancellationToken ct)
    {
        var full = await aggregator.GetDetailsAsync(type, winner.ExternalId, winner.Title, ct, winner.ExternalSource);
        if (full is null)
        {
            return false;
        }

        return await PendingMatchApplier.ApplyAsync(db, item, full, imageStorage, ct, season => db.Entry(season).State = EntityState.Added);
    }

    /// <summary>
    /// Search for one title: parallel fan-out across key providers. If a Latin / Romaji title exists,
    /// AniList and MangaDex are queried strictly by that Latin title, while Russian providers (Shikimori / Kinopoisk)
    /// are queried with the Russian/Cyrillic title. Results are merged and prioritized for exact Romaji hits.
    /// </summary>
    private static async Task<IReadOnlyList<ExternalMediaDto>> FindCandidatesAsync(
        MetadataAggregatorService aggregator,
        MediaItem item,
        string type,
        CancellationToken ct)
    {
        var romaji = item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        };

        var latin = new[] { romaji, item.OriginalTitle, MediaTitleHelper.ExtractLatinFromTitle(item.Title) }
            .FirstOrDefault(MediaTitleHelper.IsLatin)?.Trim();

        var russian = MediaTitleHelper.CleanRussianTitle(item.Title);
        var searchTasks = new List<Task<IReadOnlyList<ExternalMediaDto>>>();

        if (type == "manga")
        {
            if (!string.IsNullOrWhiteSpace(latin))
            {
                searchTasks.Add(aggregator.SearchSourceAsync("manga", latin, "anilist", ct));
                searchTasks.Add(aggregator.SearchSourceAsync("manga", latin, "mangadex", ct));
            }
            if (MediaTitleHelper.IsCyrillic(russian))
            {
                searchTasks.Add(aggregator.SearchSourceAsync("manga", russian, "shikimori", ct));
            }
        }
        else if (type == "anime")
        {
            if (!string.IsNullOrWhiteSpace(latin))
            {
                searchTasks.Add(aggregator.SearchSourceAsync("anime", latin, "anilist", ct));
            }
            if (MediaTitleHelper.IsCyrillic(russian))
            {
                searchTasks.Add(aggregator.SearchSourceAsync("anime", russian, "shikimori", ct));
            }
        }
        else if (type is "movie" or "tvshow")
        {
            if (!string.IsNullOrWhiteSpace(latin))
            {
                searchTasks.Add(aggregator.SearchSourceAsync(type, latin, "tmdb", ct));
            }
            if (MediaTitleHelper.IsCyrillic(russian))
            {
                searchTasks.Add(aggregator.SearchSourceAsync(type, russian, "kinopoisk", ct));
            }
        }

        if (searchTasks.Count == 0)
        {
            searchTasks.Add(aggregator.SearchAsync(type, latin ?? item.Title, ct).AsTask());
        }

        var resultsGroups = await Task.WhenAll(searchTasks);
        var found = new List<ExternalMediaDto>(resultsGroups.SelectMany(g => g));

        // Cyrillic-only roundtrip: if no Latin title was known, but Shikimori returned candidates with Romaji
        if (found.Count > 0 && string.IsNullOrWhiteSpace(latin) && type is "anime" or "manga")
        {
            var romajiFromFallback = found
                .Select(candidate => candidate.RomajiTitle ?? candidate.OriginalTitle)
                .FirstOrDefault(MediaTitleHelper.IsLatin);

            if (!string.IsNullOrWhiteSpace(romajiFromFallback))
            {
                var secondaryTasks = new List<Task<IReadOnlyList<ExternalMediaDto>>>
                {
                    aggregator.SearchSourceAsync(type, romajiFromFallback, "anilist", ct)
                };
                if (type == "manga")
                {
                    secondaryTasks.Add(aggregator.SearchSourceAsync("manga", romajiFromFallback, "mangadex", ct));
                }

                var secondaryResults = await Task.WhenAll(secondaryTasks);
                found.AddRange(secondaryResults.SelectMany(g => g));
            }
        }

        if (found.Count == 0)
        {
            var fallback = await aggregator.SearchAsync(type, item.Title, ct);
            found.AddRange(fallback);
        }

        return found
            .Where(candidate => !string.IsNullOrWhiteSpace(candidate.ExternalId))
            .DistinctBy(candidate => $"{candidate.ExternalSource}\u001f{candidate.ExternalId}", StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(candidate =>
            {
                if (string.IsNullOrWhiteSpace(latin)) return 0;
                var isAniListOrMangaDex = candidate.ExternalSource is not null &&
                    (candidate.ExternalSource.Equals("AniList", StringComparison.OrdinalIgnoreCase) ||
                     candidate.ExternalSource.Equals("MangaDex", StringComparison.OrdinalIgnoreCase));
                if (!isAniListOrMangaDex) return 0;
                var titleScore = Math.Max(
                    ImportMatchScorer.TitlePairScore(latin, candidate.Title),
                    Math.Max(
                        ImportMatchScorer.TitlePairScore(latin, candidate.RomajiTitle),
                        ImportMatchScorer.TitlePairScore(latin, candidate.OriginalTitle)));
                return titleScore >= 60 ? 2 : (titleScore >= 40 ? 1 : 0);
            })
            .ToList();
    }

    private static Task<MediaItem?> LoadAsync(AppDbContext db, Guid mediaId, CancellationToken ct) =>
        db.MediaItems
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
            .AsSplitQuery()
            .SingleOrDefaultAsync(media => media.Id == mediaId, ct);

    private static void EvictStatsCaches(IServiceProvider services)
    {
        var cache = services.GetService<Microsoft.Extensions.Caching.Memory.IMemoryCache>();
        cache?.Remove(AdvancedStatsCalculator.CacheKey);
        cache?.Remove(TasteProfileCalculator.CacheKey);
    }
}
