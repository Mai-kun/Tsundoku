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
        var priorities = await services.GetRequiredService<ISourcePriorityService>().GetPrioritiesAsync(type, ct);
        var candidates = await FindCandidatesAsync(aggregator, item, type, priorities, ct);
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
    /// are queried with the Russian/Cyrillic title. From every source only the top 4 matches are kept,
    /// and the merged list is sorted strictly by the source position in <paramref name="sourcePriorities"/>
    /// and then by match score, so candidates from the first source (AniList) always surface first.
    /// </summary>
    private static async Task<IReadOnlyList<ExternalMediaDto>> FindCandidatesAsync(
        MetadataAggregatorService aggregator,
        MediaItem item,
        string type,
        IReadOnlyList<string> sourcePriorities,
        CancellationToken ct)
    {
        var rawRomaji = (item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        })?.Trim();

        var latin = (!string.IsNullOrWhiteSpace(rawRomaji) ? rawRomaji : null)
            ?? item.OriginalTitle?.Trim()
            ?? MediaTitleHelper.ExtractLatinFromTitle(item.Title)?.Trim();

        if (!string.IsNullOrWhiteSpace(latin) && latin.Contains('-') && !latin.Contains(' '))
        {
            latin = latin.Replace('-', ' ');
        }

        var russian = MediaTitleHelper.CleanRussianTitle(item.Title);
        var searchTasks = new List<(string Source, Task<IReadOnlyList<ExternalMediaDto>> Task)>();

        void Add(string source, Task<IReadOnlyList<ExternalMediaDto>> task) =>
            searchTasks.Add((source, task));

        if (type == "manga")
        {
            // Always query all active manga providers (AniList + MangaDex + Shikimori).
            // When RomajiTitle / Latin exists, strictly query AniList and MangaDex with it.
            if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("anilist", aggregator.SearchSourceAsync("manga", latin, "anilist", ct));
                Add("mangadex", aggregator.SearchSourceAsync("manga", latin, "mangadex", ct));
            }
            else
            {
                Add("anilist", aggregator.SearchSourceAsync("manga", item.Title, "anilist", ct));
                Add("mangadex", aggregator.SearchSourceAsync("manga", item.Title, "mangadex", ct));
            }

            if (MediaTitleHelper.IsCyrillic(russian))
            {
                Add("shikimori", aggregator.SearchSourceAsync("manga", russian, "shikimori", ct));
            }
            else if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("shikimori", aggregator.SearchSourceAsync("manga", latin, "shikimori", ct));
            }
            else
            {
                Add("shikimori", aggregator.SearchSourceAsync("manga", item.Title, "shikimori", ct));
            }
        }
        else if (type == "anime")
        {
            if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("anilist", aggregator.SearchSourceAsync("anime", latin, "anilist", ct));
            }
            else
            {
                Add("anilist", aggregator.SearchSourceAsync("anime", item.Title, "anilist", ct));
            }

            if (MediaTitleHelper.IsCyrillic(russian))
            {
                Add("shikimori", aggregator.SearchSourceAsync("anime", russian, "shikimori", ct));
            }
            else if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("shikimori", aggregator.SearchSourceAsync("anime", latin, "shikimori", ct));
            }
            else
            {
                Add("shikimori", aggregator.SearchSourceAsync("anime", item.Title, "shikimori", ct));
            }
        }
        else if (type is "movie" or "tvshow")
        {
            if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("tmdb", aggregator.SearchSourceAsync(type, latin, "tmdb", ct));
            }
            if (MediaTitleHelper.IsCyrillic(russian))
            {
                Add("kinopoisk", aggregator.SearchSourceAsync(type, russian, "kinopoisk", ct));
            }
            else if (!string.IsNullOrWhiteSpace(latin))
            {
                Add("kinopoisk", aggregator.SearchSourceAsync(type, latin, "kinopoisk", ct));
            }
        }

        if (searchTasks.Count == 0)
        {
            Add("", aggregator.SearchAsync(type, latin ?? item.Title, ct).AsTask());
        }

        var primary = await Task.WhenAll(searchTasks.Select(task => task.Task));

        var collected = new List<(string Source, ExternalMediaDto Dto)>();
        for (var i = 0; i < primary.Length; i++)
        {
            foreach (var dto in primary[i])
            {
                if (!string.IsNullOrWhiteSpace(dto.ExternalId))
                {
                    collected.Add((searchTasks[i].Source, dto));
                }
            }
        }

        // Cyrillic-only roundtrip: if no Latin title was known, but Shikimori returned candidates with Romaji
        if (collected.Count > 0 && string.IsNullOrWhiteSpace(latin) && type is "anime" or "manga")
        {
            var romajiFromFallback = collected
                .Select(candidate => candidate.Dto.RomajiTitle ?? candidate.Dto.OriginalTitle)
                .FirstOrDefault(s => !string.IsNullOrWhiteSpace(s) && MediaTitleHelper.IsLatin(s));

            if (!string.IsNullOrWhiteSpace(romajiFromFallback))
            {
                var secondary = new List<(string Source, Task<IReadOnlyList<ExternalMediaDto>> Task)>
                {
                    ("anilist", aggregator.SearchSourceAsync(type, romajiFromFallback, "anilist", ct)),
                };
                if (type == "manga")
                {
                    secondary.Add(("mangadex", aggregator.SearchSourceAsync("manga", romajiFromFallback, "mangadex", ct)));
                }

                var secondaryResults = await Task.WhenAll(secondary.Select(task => task.Task));
                for (var i = 0; i < secondaryResults.Length; i++)
                {
                    foreach (var dto in secondaryResults[i])
                    {
                        if (!string.IsNullOrWhiteSpace(dto.ExternalId))
                        {
                            collected.Add((secondary[i].Source, dto));
                        }
                    }
                }
            }
        }

        if (collected.Count == 0)
        {
            var fallback = await aggregator.SearchAsync(type, item.Title, ct);
            foreach (var dto in fallback)
            {
                if (!string.IsNullOrWhiteSpace(dto.ExternalId))
                {
                    collected.Add((string.Empty, dto));
                }
            }
        }

        var rank = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < sourcePriorities.Count; i++)
        {
            rank.TryAdd(sourcePriorities[i], i);
        }

        var scored = collected
            .Select(candidate =>
            {
                var src = !string.IsNullOrWhiteSpace(candidate.Source) ? candidate.Source : candidate.Dto.ExternalSource;
                return (
                    Source: src ?? string.Empty,
                    candidate.Dto,
                    Score: ImportMatchScorer.ScoreCandidate(item, candidate.Dto),
                    SourceRank: rank.TryGetValue(src ?? string.Empty, out var r) ? r : int.MaxValue
                );
            })
            .ToList();

        // До 4 лучших результатов от каждого источника.
        var capped = scored
            .GroupBy(candidate => candidate.Source, StringComparer.OrdinalIgnoreCase)
            .SelectMany(group => group.OrderByDescending(candidate => candidate.Score).Take(4))
            .ToList();

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        return capped
            .Where(candidate => seen.Add($"{candidate.Dto.ExternalSource}\u001f{candidate.Dto.ExternalId}"))
            .OrderBy(candidate => candidate.SourceRank)
            .ThenByDescending(candidate => candidate.Score)
            .Select(candidate => candidate.Dto)
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
        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
    }
}
