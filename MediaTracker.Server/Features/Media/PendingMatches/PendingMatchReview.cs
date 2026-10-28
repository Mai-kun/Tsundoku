using Dapper;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Features.Media.PendingMatches;

/// <summary>
/// One row of the "review ambiguous matches" screen: the library title as the user imported it plus
/// the candidate matches the scorer could not decide between. Frontend renders these side by side.
/// </summary>
public sealed record PendingMatchReviewDto
{
    public required Guid Id { get; init; }
    public required string Title { get; init; }
    public string? RomajiTitle { get; init; }
    public required string Type { get; init; }
    public bool? IsAnime { get; init; }
    public int? ReleaseYear { get; init; }
    public string? Author { get; init; }
    public int? CurrentProgress { get; init; }
    public int? TotalCount { get; init; }
    public IReadOnlyList<ExternalMediaDto> Candidates { get; init; } = [];
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

    private static PendingMatchReviewDto ToDto(MediaItem item) => new()
    {
        Id = item.Id,
        Title = item.Title,
        RomajiTitle = (item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        }) ?? MediaTitleHelper.ExtractLatinFromTitle(item.Title),
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
        Candidates = MediaJsonCache.Deserialize<ExternalMediaDto>(item.PendingMatchesJson),
    };

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

        jobs?.Enqueue(
            item.Id,
            item.Title,
            PendingMatchEnrichment.CreateWork(
                item.Id,
                request.ExternalId,
                request.Source,
                request.Type,
                request.Title,
                logger));

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
                    resolvedType,
                    externalId,
                    title ?? current.Title,
                    source,
                    token);
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
            }
            catch (Exception ex)
            {
                try
                {
                    current.SyncStatus = SyncStatus.Failed;
                    current.MarkUpdated();
                    await scopedDb.UpdateMediaItemAsync(current, CancellationToken.None);
                }
                catch
                {
                }
                logger?.LogWarning(ex, "Enrichment for media {MediaId} failed", mediaId);
                throw;
            }
        };

    /// <summary>
    /// A rate-limited provider (429 lands here as SourceUnavailableException) gets the same treatment
    /// as the batch import: a pause and another try before the job is marked failed.
    /// </summary>
    private static async Task<ExternalMediaDto?> FetchWithRetryAsync(
        MetadataAggregatorService aggregator,
        string type,
        string externalId,
        string title,
        string source,
        CancellationToken ct)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await aggregator.GetDetailsAsync(type, externalId, title, ct, source);
            }
            catch (SourceUnavailableException) when (attempt < 3)
            {
                await Task.Delay(2500, ct);
            }
        }
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
        return true;
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

        return pending.Count;
    }
}
