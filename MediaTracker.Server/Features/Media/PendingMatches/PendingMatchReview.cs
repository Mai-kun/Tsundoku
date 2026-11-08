using System.Text.Json;
using Dapper;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.DeleteMedia;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.Media.PendingMatches;

/// <summary>
/// The object shape stored in <c>PendingMatchesJson</c> when a freshly added title hit the
/// duplicate guard: the row awaits the merge-vs-keep verdict, and the marker points at the library
/// title it collided with. (Ambiguous import matches keep the array-of-candidates shape.)
/// </summary>
public sealed record DuplicateConflictDto(
    string ConflictType,
    Guid ExistingMediaId,
    string ExistingTitle,
    string? IncomingSource,
    string? IncomingExternalId,
    string? IncomingTitle);

/// <summary>
/// One row of the "review ambiguous matches" screen: the library title as the user imported it plus
/// the candidate matches the scorer could not decide between. Frontend renders these side by side.
/// </summary>
public sealed record PendingMatchReviewDto
{
    public required Guid Id { get; init; }
    public required string Title { get; init; }
    public string? RomajiTitle { get; init; }
    public string? OriginalTitle { get; init; }
    public IReadOnlyList<string>? AltTitles { get; init; }
    public required string Type { get; init; }
    public bool? IsAnime { get; init; }
    public int? ReleaseYear { get; init; }
    public string? Author { get; init; }
    public int? CurrentProgress { get; init; }
    public int? TotalCount { get; init; }
    public string? CountryOfOrigin { get; init; }
    public string? MangaFormat { get; init; }
    public IReadOnlyList<ExternalMediaDto> Candidates { get; init; } = [];
    /// <summary>Set when the row is a duplicate-conflict phantom, not an ambiguous import match.</summary>
    public DuplicateConflictDto? Duplicate { get; init; }
}

public interface IGetPendingMatchesHandler
{
    Task<IReadOnlyList<PendingMatchReviewDto>> HandleAsync(CancellationToken ct);
}

public sealed class GetPendingMatchesHandler(AppDbContext db) : IGetPendingMatchesHandler
{
    public async Task<IReadOnlyList<PendingMatchReviewDto>> HandleAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT * FROM MediaItems
            WHERE SyncStatus = @syncStatus
            ORDER BY CreatedAt;
            """;
        cmd.Parameters.Add(new SqliteParameter("@syncStatus", (int)SyncStatus.NeedsReview));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var items = new List<MediaItem>();
        while (await reader.ReadAsync(ct))
        {
            var row = AppDbContext.ReadMediaItemRow(reader);
            var item = row.ToEntity();
            if (row.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow && item is TvShow show)
            {
                // CurrentProgress/TotalCount are summed from the season list; raw rows carry no seasons.
                show.Seasons = await AppDbContext.LoadTvSeasons(conn, row.Id, ct);
            }
            items.Add(item);
        }

        return [.. items.Select(ToDto)];
    }

    private static PendingMatchReviewDto ToDto(MediaItem item)
    {
        var (candidates, conflict) = ParsePending(item.PendingMatchesJson);
        return new()
        {
            Id = item.Id,
            Title = item.Title,
            RomajiTitle = (item switch
            {
                Manga manga => manga.RomajiTitle,
                Movie movie => movie.RomajiTitle,
                TvShow show => show.RomajiTitle,
                _ => null,
            }) ?? MediaMetadataApplier.DeserializeAltTitles(item.AltTitles).FirstOrDefault(MediaTitleHelper.IsLatin)
               ?? (MediaTitleHelper.IsLatin(item.OriginalTitle) ? item.OriginalTitle : null)
               ?? MediaTitleHelper.ExtractLatinFromTitle(item.Title),
            OriginalTitle = item.OriginalTitle,
            AltTitles = MediaMetadataApplier.DeserializeAltTitles(item.AltTitles),
            Type = MediaResponseMapper.GetType(item),
            IsAnime = item switch { Movie movie => movie.IsAnime, TvShow show => show.IsAnime, _ => null },
            ReleaseYear = item.ReleaseYear,
            Author = item switch
            {
                Book book => book.Author,
                Manga manga => manga.Author,
                _ => null,
            },
            CurrentProgress = Progress(item),
            TotalCount = Total(item),
            CountryOfOrigin = item.CountryOfOrigin,
            MangaFormat = item switch { Manga manga => manga.Format, _ => null },
            Candidates = candidates,
            Duplicate = conflict,
        };
    }

    /// <summary>
    /// Two payload shapes share the blob: ambiguous imports store a candidate array, duplicate
    /// conflicts store a single marker object. The first character is the discriminator, and an
    /// unreadable payload reads as empty rather than breaking the review list.
    /// </summary>
    private static (IReadOnlyList<ExternalMediaDto> Candidates, DuplicateConflictDto? Conflict) ParsePending(string? json)
    {
        var trimmed = json?.TrimStart();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return ([], null);
        }

        if (trimmed.StartsWith('{'))
        {
            try
            {
                var marker = JsonSerializer.Deserialize(trimmed, AppJsonSerializerContext.Default.DuplicateConflictDto);
                if (marker is not null)
                {
                    return ([], marker);
                }
            }
            catch (JsonException)
            {
            }

            return ([], null);
        }

        return (MediaJsonCache.Deserialize<ExternalMediaDto>(json), null);
    }

    private static int? Progress(MediaItem item) => item switch
    {
        Book book => book.CurrentPage,
        Manga manga => manga.CurrentChapter,
        VideoGame game => (int?)game.HoursPlayed,
        TvShow show => show.Seasons?.Sum(season => season.CurrentEpisode) is int watched && watched > 0 ? watched : null,
        _ => null,
    };

    private static int? Total(MediaItem item) => item switch
    {
        Book book => (book.TotalPages is > 0) ? book.TotalPages : null,
        Manga manga => (manga.TotalChapters is > 0) ? manga.TotalChapters : null,
        VideoGame => null,
        TvShow show => show.Seasons?.Sum(season => season.TotalEpisodes) is int total && total > 0 ? total : null,
        _ => null,
    };
}

public sealed record ResolveMatchRequest(string ExternalId, string Source, string? Type = null, string? Title = null);

public sealed record ResolveMatchCommand(Guid MediaId, ResolveMatchRequest Request);

public interface IResolveMatchHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(ResolveMatchCommand command, CancellationToken ct);
}

/// <summary>
/// Applies the candidate the user confirmed without blocking the HTTP request: the pick itself
/// (source id + name) is recorded in one fast transaction and the external download runs in the
/// job queue — no provider call inside the HTTP request, so a burst of quick picks can no longer
/// trip provider 429s.
/// </summary>
public sealed class ResolveMatchHandler(
    AppDbContext db,
    IJobManager? jobs = null,
    ILogger<ResolveMatchHandler>? logger = null) : IResolveMatchHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(ResolveMatchCommand command, CancellationToken ct)
    {
        var request = command.Request;
        if (string.IsNullOrWhiteSpace(request.ExternalId) || string.IsNullOrWhiteSpace(request.Source))
        {
            return Result<MediaDetailDto>.Failure(Error.Validation("ExternalId and Source are required."));
        }

        var item = await db.LoadMediaItemAsync(command.MediaId, ct);
        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.MediaId}' was not found."));
        }

        // Record the user's choice immediately; the provider covers and ratings arrive with the job.
        item.ImportSource ??= item.ExternalSource;
        item.ExternalId = request.ExternalId;
        item.ExternalSource = request.Source;
        item.SyncStatus = SyncStatus.Syncing;
        item.PendingMatchesJson = null;
        item.MarkUpdated();
        await db.UpdateMediaItemAsync(item, ct);
        MediaListCache.Invalidate();

        jobs?.Enqueue(
            item.Id,
            item.Title,
            PendingMatchEnrichment.CreateWork(
                item.Id,
                request.ExternalId,
                request.Source,
                request.Type,
                request.Title,
                logger),
            highPriority: true);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}

/// <summary>
/// Background work shared by the single-title review and the bulk "resolve by source priority":
/// fetches the chosen candidate's full details through the throttled queue (with the batch-import
/// retry on rate-limited providers) and lets <see cref="PendingMatchApplier"/> fill the row.
/// </summary>
internal static class PendingMatchEnrichment
{
    public static Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> CreateWork(
        Guid mediaId,
        string externalId,
        string source,
        string? type,
        string? title,
        ILogger? logger) =>
        async (sp, token, progress) =>
        {
            var scopedDb = sp.GetRequiredService<AppDbContext>();
            var aggregator = sp.GetRequiredService<MetadataAggregatorService>();
            var imageStorage = sp.GetRequiredService<IImageStorageService>();
            var cache = sp.GetRequiredService<IMemoryCache>();

            var current = await scopedDb.LoadMediaItemAsync(mediaId, token);

            if (current is null) return;

            try
            {
                progress.Report(new JobProgressDto(
                    Guid.Empty, null, string.Empty, 20, "Загрузка данных выбранного совпадения", JobStatus.Running, DateTime.MinValue, null));

                var resolvedType = type ?? AggregatorTypes.Resolve(current);
                var details = await FetchWithRetryAsync(
                    aggregator,
                    sp,
                    resolvedType,
                    externalId,
                    title ?? current.Title,
                    source,
                    token,
                    progress);
                if (details is null)
                {
                    throw new InvalidOperationException("Не удалось получить данные выбранного кандидата от источника.");
                }

                progress.Report(new JobProgressDto(
                    Guid.Empty, null, string.Empty, 60, "Обновление обложки и связей", JobStatus.Running, DateTime.MinValue, null));

                await PendingMatchApplier.ApplyAsync(
                    scopedDb,
                    current,
                    details,
                    imageStorage,
                    token,
                    _ => { });

                AdvancedStatsCalculator.InvalidateCache(cache);
                TasteProfileCalculator.InvalidateCache(cache);
                MediaListCache.Invalidate();
            }
            catch (Exception ex)
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
                logger?.LogWarning(ex, "Enrichment for media {MediaId} failed", mediaId);
                throw;
            }
        };

    /// <summary>
    /// A rate-limited provider (429 lands here as SourceUnavailableException) gets backoff treatment:
    /// wait for the limit to reset before retrying so manual user choices do not fail.
    /// </summary>
    private static async Task<ExternalMediaDto?> FetchWithRetryAsync(
        MetadataAggregatorService aggregator,
        IServiceProvider sp,
        string type,
        string externalId,
        string title,
        string source,
        CancellationToken ct,
        IProgress<JobProgressDto>? progress = null)
    {
        for (var attempt = 1; attempt <= 5; attempt++)
        {
            try
            {
                var rateLimiter = sp.GetService<RateLimitTracker>();
                var status = rateLimiter?.GetStatus(source);
                if (status is not null && status.Remaining <= 2 && status.ResetSecondsRemaining > 0)
                {
                    var waitSec = status.ResetSecondsRemaining;
                    progress?.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 20,
                        $"Ожидание сброса лимита {status.Provider} ({waitSec} сек)...",
                        JobStatus.Running, DateTime.MinValue, null));
                    await Task.Delay(TimeSpan.FromSeconds(waitSec + 2), ct);
                }

                return await aggregator.GetDetailsAsync(type, externalId, title, ct, source);
            }
            catch (SourceUnavailableException ex)
            {
                var is429 = ex.Message.Contains("429") ||
                            ex.InnerException is HttpRequestException { StatusCode: global::System.Net.HttpStatusCode.TooManyRequests };

                if (is429 && attempt < 5)
                {
                    var rateLimiter = sp.GetService<RateLimitTracker>();
                    var status = rateLimiter?.GetStatus(source);
                    var waitSec = status?.ResetSecondsRemaining is > 0 ? status.ResetSecondsRemaining : 60;

                    progress?.Report(new JobProgressDto(
                        Guid.Empty, null, string.Empty, 20,
                        $"Ожидание сброса лимита {source} ({waitSec} сек)...",
                        JobStatus.Running, DateTime.MinValue, null));

                    await Task.Delay(TimeSpan.FromSeconds(waitSec + 2), ct);
                    continue;
                }

                if (attempt < 3 && !is429)
                {
                    await Task.Delay(2500, ct);
                    continue;
                }

                throw;
            }
        }

        return null;
    }
}

public sealed record ResolveAllByPriorityResult(int ResolvedCount, int SkippedCount);

public interface IResolveAllByPriorityHandler
{
    Task<ResolveAllByPriorityResult> HandleAsync(CancellationToken ct);
}

/// <summary>
/// "Pick every review row's top candidate": the queued candidate lists are ranked by the scorer, so
/// the first entry IS the best match. Rows whose best candidate scores below the bulk threshold stay
/// in review on purpose — a 10-20 score is a wrong-title trap, not a preference question. Each kept
/// row goes to the same background enrichment as a single pick; the request only records the choices.
/// </summary>
public sealed class ResolveAllByPriorityHandler(AppDbContext db, IJobManager? jobs = null) : IResolveAllByPriorityHandler
{
    /// <summary>Minimum confidence a top candidate must reach to be bulk-applied automatically.</summary>
    private const int BulkPickScore = 50;

    public async Task<ResolveAllByPriorityResult> HandleAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT * FROM MediaItems
            WHERE SyncStatus = @syncStatus;
            """;
        cmd.Parameters.Add(new SqliteParameter("@syncStatus", (int)SyncStatus.NeedsReview));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var pending = new List<MediaItem>();
        while (await reader.ReadAsync(ct))
        {
            pending.Add(AppDbContext.ReadMediaItemRow(reader).ToEntity());
        }

        var queued = new List<(MediaItem Item, ExternalMediaDto Top)>();

        foreach (var item in pending)
        {
            // A duplicate-conflict row carries a marker object, not a candidate list: its verdict is
            // merge-vs-keep, which the bulk "pick the best candidate" pass must not touch.
            if (item.PendingMatchesJson?.TrimStart().StartsWith('{') is true)
            {
                continue;
            }

            var top = MediaJsonCache
                .Deserialize<ExternalMediaDto>(item.PendingMatchesJson)
                ?.FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate.ExternalId));

            if (top is null || ImportMatchScorer.ScoreCandidate(item, top) < BulkPickScore)
            {
                // Weak or empty match: the row stays in review for a manual search or deletion.
                continue;
            }

            item.ImportSource ??= item.ExternalSource;
            item.ExternalId = top.ExternalId;
            item.ExternalSource = top.ExternalSource;
            item.SyncStatus = SyncStatus.Syncing;
            item.PendingMatchesJson = null;
            item.MarkUpdated();
            queued.Add((item, top));
        }

        foreach (var (item, _) in queued)
        {
            await db.UpdateMediaItemAsync(item, ct);
        }

        MediaListCache.Invalidate();

        foreach (var (item, top) in queued)
        {
            jobs?.Enqueue(
                item.Id,
                item.Title,
                PendingMatchEnrichment.CreateWork(
                    item.Id,
                    top.ExternalId!,
                    top.ExternalSource!,
                    top.Type,
                    top.Title,
                    null));
        }

        return new ResolveAllByPriorityResult(queued.Count, pending.Count - queued.Count);
    }
}

public sealed record DismissMatchCommand(Guid MediaId);

public interface IDismissMatchHandler
{
    Task<bool> HandleAsync(DismissMatchCommand command, CancellationToken ct);
}

public sealed class DismissMatchHandler(AppDbContext db) : IDismissMatchHandler
{
    public async Task<bool> HandleAsync(DismissMatchCommand command, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var itemRow = await conn.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT * FROM MediaItems WHERE Id = @id;",
            new { id = command.MediaId.ToString().ToUpperInvariant() });

        if (itemRow is null)
        {
            return false;
        }

        var mediaItem = itemRow.ToEntity();
        PendingMatchApplier.Dismiss(mediaItem);
        await db.UpdateMediaItemAsync(mediaItem, ct);
        MediaListCache.Invalidate();
        return true;
    }
}

public sealed record MergeDuplicateCommand(Guid ExistingMediaId, Guid DuplicateMediaId);

public interface IMergeDuplicateHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(MergeDuplicateCommand command, CancellationToken ct);
}

/// <summary>
/// "Объединить источники" on a duplicate-conflict review card: the duplicate row's external
/// bindings, ratings and any missing counts/synopsis join the kept title, then the duplicate row
/// leaves the library for good and a background pass fills the remaining gaps from the newly
/// bound source (studio, rating, cast...). The library keeps ONE card with both sources.
/// </summary>
public sealed class MergeDuplicateHandler(
    AppDbContext db,
    IDeleteMediaHandler deleteMedia,
    IJobManager jobs) : IMergeDuplicateHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(MergeDuplicateCommand command, CancellationToken ct)
    {
        if (command.ExistingMediaId == command.DuplicateMediaId)
        {
            return Result<MediaDetailDto>.Failure(
                Error.Validation("Нельзя объединять тайтл с самим собой."));
        }

        var existing = await db.LoadMediaItemAsync(command.ExistingMediaId, ct);
        if (existing is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.ExistingMediaId}' was not found."));
        }

        var duplicate = await db.LoadMediaItemAsync(command.DuplicateMediaId, ct);
        if (duplicate is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.DuplicateMediaId}' was not found."));
        }

        MergeSources(existing, duplicate);
        var seasonsAdded = EnrichGaps(existing, duplicate);
        MergeRatings(existing, duplicate);

        existing.MarkUpdated();
        await db.UpdateMediaItemAsync(existing, ct);
        if (seasonsAdded && existing is TvShow show)
        {
            foreach (var season in show.Seasons)
            {
                await db.InsertTvSeasonAsync(season, ct);
            }
        }

        MediaListCache.Invalidate();

        // The duplicate row (and its covers) leaves the library entirely.
        await deleteMedia.HandleAsync(new DeleteMediaCommand(command.DuplicateMediaId), ct);

        // Binding the source alone does not move its data over: fill the kept row's gaps from the
        // newly bound provider in the background (studio, rating, cast...), the same promise the
        // "Внешние источники" panel makes when a source is linked by hand.
        if (!string.IsNullOrWhiteSpace(duplicate.ExternalSource)
            && !string.IsNullOrWhiteSpace(duplicate.ExternalId))
        {
            existing.SyncStatus = SyncStatus.Syncing;
            existing.MarkUpdated();
            await db.UpdateMediaItemAsync(existing, ct);
            MediaListCache.Invalidate();

            jobs.Enqueue(
                existing.Id,
                existing.Title,
                CreateEnrichmentWork(existing.Id, duplicate.ExternalSource, duplicate.ExternalId),
                highPriority: true);
        }

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(existing));
    }

    /// <summary>
    /// Fetches the duplicate's record from ITS provider (the duplicate's own external id, not the
    /// kept row's) and gap-fills the kept row. Best effort: a provider failure leaves the merged
    /// row as it is, Ready and fully usable.
    /// </summary>
    private static Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> CreateEnrichmentWork(
        Guid mediaId,
        string source,
        string externalId) =>
        async (sp, token, progress) =>
        {
            var scopedDb = sp.GetRequiredService<AppDbContext>();
            var aggregator = sp.GetRequiredService<MetadataAggregatorService>();
            var cache = sp.GetRequiredService<IMemoryCache>();

            var current = await scopedDb.LoadMediaItemAsync(mediaId, token);
            if (current is null) return;

            try
            {
                progress.Report(new JobProgressDto(
                    Guid.Empty, null, string.Empty, 20, "Загрузка данных нового источника", JobStatus.Running, DateTime.MinValue, null));

                ExternalMediaDto? details;
                try
                {
                    details = await aggregator.GetDetailsAsync(
                        AggregatorTypes.Resolve(current),
                        externalId,
                        current.Title,
                        token,
                        source);
                }
                catch (SourceUnavailableException)
                {
                    // The new source is unreachable: the merged row stays as it is, no failure.
                    details = null;
                }

                progress.Report(new JobProgressDto(
                    Guid.Empty, null, string.Empty, 60, "Дополнение данных", JobStatus.Running, DateTime.MinValue, null));

                if (details is not null && MediaMetadataApplier.ApplyIfMissing(current, details, _ => { }))
                {
                    if (current is TvShow show)
                    {
                        foreach (var season in show.Seasons)
                        {
                            await scopedDb.InsertTvSeasonAsync(season, token);
                        }
                    }

                    current.SyncStatus = SyncStatus.Ready;
                    current.MarkUpdated();
                    await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                    MediaListCache.Invalidate();
                    AdvancedStatsCalculator.InvalidateCache(cache);
                    TasteProfileCalculator.InvalidateCache(cache);
                }
                else
                {
                    current.SyncStatus = SyncStatus.Ready;
                    current.MarkUpdated();
                    await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                    MediaListCache.Invalidate();
                }
            }
            catch
            {
                try
                {
                    current.SyncStatus = SyncStatus.Ready;
                    current.MarkUpdated();
                    await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                    MediaListCache.Invalidate();
                }
                catch
                {
                }
            }
        };

    /// <summary>
    /// Every external binding the duplicate carried joins the kept row. The primary flag never
    /// moves: the title the user already had keeps its crowned source.
    /// </summary>
    private static void MergeSources(MediaItem existing, MediaItem duplicate)
    {
        var sources = LinkedSourceCatalog.GetFor(existing);
        foreach (var source in LinkedSourceCatalog.GetFor(duplicate))
        {
            if (string.IsNullOrWhiteSpace(source.ExternalId)
                || source.Source.StartsWith("offline", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (sources.Any(s => s.Source.Equals(source.Source, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            sources.Add(source with { IsPrimary = false });
        }

        LinkedSourceCatalog.SaveFor(existing, sources);
    }

    /// <summary>
    /// Only true gaps are filled: the kept row's own values always win. Seasons transfer only when
    /// the kept show has none at all.
    /// </summary>
    private static bool EnrichGaps(MediaItem existing, MediaItem duplicate)
    {
        if (string.IsNullOrWhiteSpace(existing.Description)
            && !string.IsNullOrWhiteSpace(duplicate.Description))
        {
            existing.Description = duplicate.Description;
        }

        switch (existing, duplicate)
        {
            case (TvShow show, TvShow dupShow) when show.Seasons.Count == 0 && dupShow.Seasons.Count > 0:
                foreach (var season in dupShow.Seasons)
                {
                    show.Seasons.Add(new TvSeason
                    {
                        Id = season.Id,
                        SeasonNumber = season.SeasonNumber,
                        Title = season.Title,
                        CoverUrl = season.CoverUrl,
                        TotalEpisodes = season.TotalEpisodes,
                        AirDate = season.AirDate,
                        EpisodesData = season.EpisodesData,
                        TvShowId = show.Id,
                        TvShow = show,
                    });
                }
                return true;

            case (Manga manga, Manga dupManga):
                if (manga.TotalChapters is not > 0 && dupManga.TotalChapters is > 0)
                {
                    manga.RecordTotalChapters(dupManga.TotalChapters.Value);
                }
                if (manga.TotalVolumes is not > 0 && dupManga.TotalVolumes is > 0)
                {
                    manga.RecordTotalVolumes(dupManga.TotalVolumes.Value);
                }
                break;

            case (Book book, Book dupBook):
                if (book.TotalPages == 0 && dupBook.TotalPages > 0)
                {
                    book.TotalPages = dupBook.TotalPages;
                }
                if (book.TotalChapters is not > 0 && dupBook.TotalChapters is > 0)
                {
                    book.TotalChapters = dupBook.TotalChapters;
                }
                break;
        }

        return false;
    }

    /// <summary>
    /// The new source's rating joins the stored rating list (union by normalized source); the
    /// headline number only moves when the kept row had none.
    /// </summary>
    private static void MergeRatings(MediaItem existing, MediaItem duplicate)
    {
        try
        {
            List<MediaMetadataApplier.StoredRating> stored = [];
            if (!string.IsNullOrWhiteSpace(existing.ExternalRatingsJson))
            {
                stored = JsonSerializer.Deserialize(
                    existing.ExternalRatingsJson, AppJsonSerializerContext.Default.ListStoredRating) ?? [];
            }

            List<MediaMetadataApplier.StoredRating> incoming = [];
            if (!string.IsNullOrWhiteSpace(duplicate.ExternalRatingsJson))
            {
                incoming = JsonSerializer.Deserialize(
                    duplicate.ExternalRatingsJson, AppJsonSerializerContext.Default.ListStoredRating) ?? [];
            }

            if (incoming.Count > 0)
            {
                var merged = new List<RatingSnapshot>(
                    stored.Select(row => new RatingSnapshot(row.Source, row.Score, row.Votes)));
                foreach (var row in incoming)
                {
                    if (string.IsNullOrWhiteSpace(row.Source)
                        || merged.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == MediaMerger.NormalizeSourceKey(row.Source)))
                    {
                        continue;
                    }
                    merged.Add(new RatingSnapshot(row.Source, row.Score, row.Votes));
                }

                existing.ExternalRatingsJson = MediaRatingSerializer.Serialize(merged);
            }
        }
        catch (JsonException)
        {
            // An unreadable payload on either side keeps the kept row's ratings untouched.
        }

        if (existing.ExternalRating is null or 0 && duplicate.ExternalRating is > 0)
        {
            existing.ExternalRating = duplicate.ExternalRating;
            existing.ExternalRatingVotes ??= duplicate.ExternalRatingVotes;
        }
    }
}

public interface IDismissAllMatchesHandler
{
    Task<int> HandleAsync(CancellationToken ct);
}

/// <summary>
/// "Skip all": every NeedsReview row the user does not want to walk through right now goes back to
/// a calm Ready with its candidates wiped. Returns how many rows were reset for the toast.
/// </summary>
public sealed class DismissAllMatchesHandler(AppDbContext db) : IDismissAllMatchesHandler
{
    public async Task<int> HandleAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT * FROM MediaItems
            WHERE SyncStatus = @syncStatus;
            """;
        cmd.Parameters.Add(new SqliteParameter("@syncStatus", (int)SyncStatus.NeedsReview));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var pending = new List<MediaItem>();
        while (await reader.ReadAsync(ct))
        {
            pending.Add(AppDbContext.ReadMediaItemRow(reader).ToEntity());
        }

        foreach (var item in pending)
        {
            PendingMatchApplier.Dismiss(item);
            await db.UpdateMediaItemAsync(item, ct);
        }

        MediaListCache.Invalidate();
        return pending.Count;
    }
}
