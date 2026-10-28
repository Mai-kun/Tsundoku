using Dapper;
using System.Data;
using System.Globalization;
using System.IO;
using Microsoft.Data.Sqlite;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

public interface IGetMediaStatsHandler
{
    Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct);
    Task<Result<AdvancedStatsDto>> HandleAdvancedAsync(string? scope = "completed", CancellationToken ct = default);
    Task<Result<TasteProfileDto>> HandleTasteProfileAsync(string? scope = "completed", CancellationToken ct = default);
}

public sealed class GetMediaStatsHandler(AppDbContext db, IMemoryCache cache) : IGetMediaStatsHandler
{
    public async Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var totals = await conn.QueryFirstOrDefaultAsync<MediaStatsRow>(
            """
            SELECT 
                COUNT(*) as Total,
                SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END) as Completed,
                SUM(CASE WHEN Status = 1 THEN 1 ELSE 0 END) as InProgress,
                SUM(CASE WHEN Status = 0 THEN 1 ELSE 0 END) as Planned,
                SUM(CASE WHEN Status = 2 AND MediaType = 'Game' THEN 1 ELSE 0 END) as CompletedGames,
                SUM(CASE WHEN Status = 2 AND MediaType = 'Book' THEN 1 ELSE 0 END) as CompletedBooks,
                SUM(CASE WHEN Status = 2 AND MediaType = 'Movie' THEN 1 ELSE 0 END) as CompletedMovies,
                SUM(CASE WHEN MediaType = 'Game' THEN COALESCE(HoursPlayed, 0) ELSE 0 END) as TotalHoursPlayed,
                SUM(CASE WHEN MediaType = 'Book' THEN COALESCE(CurrentPage, 0) ELSE 0 END) as TotalPagesRead,
                SUM(CASE WHEN MediaType = 'Manga' THEN COALESCE(CurrentChapter, 0) ELSE 0 END) as TotalChaptersRead
            FROM MediaItems
            """);

        var totalEpisodesWatched = await conn.ExecuteScalarAsync<int?>(
            "SELECT COALESCE(SUM(CurrentEpisode), 0) FROM TvSeasons");

        var stats = new MediaStatsDto
        {
            TotalItems = totals?.Total ?? 0L,
            CompletedItems = totals?.Completed ?? 0,
            InProgressItems = totals?.InProgress ?? 0,
            PlannedItems = totals?.Planned ?? 0,
            CompletedGamesCount = totals?.CompletedGames ?? 0,
            CompletedBooksCount = totals?.CompletedBooks ?? 0,
            CompletedMoviesCount = totals?.CompletedMovies ?? 0,
            TotalHoursPlayed = totals?.TotalHoursPlayed is { } h ? (int)h : 0,
            TotalPagesRead = totals?.TotalPagesRead ?? 0,
            TotalChaptersRead = totals?.TotalChaptersRead ?? 0,
            TotalEpisodesWatched = totalEpisodesWatched ?? 0,
        };

        return Result<MediaStatsDto>.Success(stats);
    }

    public async Task<Result<AdvancedStatsDto>> HandleAdvancedAsync(string? scope = "completed", CancellationToken ct = default)
    {
        var onlyCompleted = !string.Equals(scope, "all", StringComparison.OrdinalIgnoreCase);
        var cacheKey = onlyCompleted ? AdvancedStatsCalculator.CacheKeyCompleted : AdvancedStatsCalculator.CacheKeyAll;

        if (cache.TryGetValue(cacheKey, out AdvancedStatsDto? cached) && cached is not null)
        {
            return Result<AdvancedStatsDto>.Success(cached);
        }

        var items = await LoadAllMediaItemsAsync(db, ct);

        var activityStart = DateTime.UtcNow.AddDays(-364);
        var events = await LoadRecentEventsAsync(db, activityStart, ct);

        var (bookMinutes, mangaMinutes) = await ReadReadingMinutesAsync(db, ct);

        var stats = AdvancedStatsCalculator.Calculate(
            items,
            events: events,
            bookPageMinutes: bookMinutes,
            mangaChapterMinutes: mangaMinutes,
            onlyCompleted: onlyCompleted);
        cache.Set(cacheKey, stats, TimeSpan.FromMinutes(5));

        return Result<AdvancedStatsDto>.Success(stats);
    }

    public async Task<Result<TasteProfileDto>> HandleTasteProfileAsync(string? scope = "completed", CancellationToken ct = default)
    {
        var onlyCompleted = !string.Equals(scope, "all", StringComparison.OrdinalIgnoreCase);
        var cacheKey = onlyCompleted ? TasteProfileCalculator.CacheKeyCompleted : TasteProfileCalculator.CacheKeyAll;

        if (cache.TryGetValue(cacheKey, out TasteProfileDto? cached) && cached is not null)
        {
            return Result<TasteProfileDto>.Success(cached);
        }

        var advancedStats = await HandleAdvancedAsync(scope, ct);
        if (!advancedStats.IsSuccess)
        {
            return Result<TasteProfileDto>.Failure(advancedStats.Error!);
        }

        var items = await LoadAllMediaItemsAsync(db, ct);
        var (bookMinutes, mangaMinutes) = await ReadReadingMinutesAsync(db, ct);

        var profile = TasteProfileCalculator.Calculate(items, advancedStats.Value!, bookMinutes, mangaMinutes, onlyCompleted: onlyCompleted);
        cache.Set(cacheKey, profile, TimeSpan.FromMinutes(5));

        return Result<TasteProfileDto>.Success(profile);
    }

    private static async Task<List<MediaItem>> LoadAllMediaItemsAsync(AppDbContext db, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM MediaItems";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var rows = new List<MediaItemRow>();
        while (await reader.ReadAsync(ct))
        {
            rows.Add(AppDbContext.ReadMediaItemRow(reader));
        }

        var items = new List<MediaItem>(rows.Count);
        foreach (var row in rows)
        {
            Franchise? franchise = null;
            if (row.FranchiseId != null)
            {
                using var fcmd = conn.CreateCommand();
                fcmd.CommandText = "SELECT * FROM Franchises WHERE Id = @id";
                fcmd.Parameters.Add(new SqliteParameter("@id", row.FranchiseId));
                using var freader = await fcmd.ExecuteReaderAsync(ct);
                if (await freader.ReadAsync(ct))
                {
                    franchise = new Franchise
                    {
                        Id = Guid.Parse(freader.GetString(freader.GetOrdinal("Id"))),
                        Name = freader.GetString(freader.GetOrdinal("Name")),
                        Description = freader.IsDBNull(freader.GetOrdinal("Description")) ? null : freader.GetString(freader.GetOrdinal("Description")),
                        CoverUrl = freader.IsDBNull(freader.GetOrdinal("CoverUrl")) ? null : freader.GetString(freader.GetOrdinal("CoverUrl")),
                    };
                }
            }

            List<TvSeason>? seasons = null;
            if (row.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow)
            {
                seasons = await AppDbContext.LoadTvSeasons(conn, row.Id, ct);
            }

            List<MangaVolume>? volumes = null;
            if (row.MediaType == SqliteSchemaInitializer.MediaTypes.Manga)
            {
                volumes = await AppDbContext.LoadMangaVolumes(conn, row.Id, ct);
            }

            items.Add(row.ToEntity(franchise, seasons, volumes));
        }

        return items;
    }

    private static async Task<List<MediaEvent>> LoadRecentEventsAsync(AppDbContext db, DateTime activityStart, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Events WHERE CreatedAt >= @start";
        cmd.Parameters.Add(new SqliteParameter("@start", activityStart.ToString("o")));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var events = new List<MediaEvent>();
        while (await reader.ReadAsync(ct))
        {
            events.Add(new MediaEvent
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                MediaId = Guid.Parse(reader.GetString(reader.GetOrdinal("MediaId"))),
                Type = (MediaEventType)reader.GetInt32(reader.GetOrdinal("Type")),
                OldValue = reader.IsDBNull(reader.GetOrdinal("OldValue")) ? null : reader.GetString(reader.GetOrdinal("OldValue")),
                NewValue = reader.IsDBNull(reader.GetOrdinal("NewValue")) ? null : reader.GetString(reader.GetOrdinal("NewValue")),
                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
            });
        }
        return events;
    }

    private static async Task<(double BookMinutes, double MangaMinutes)> ReadReadingMinutesAsync(AppDbContext db, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var bookVal = await conn.ExecuteScalarAsync<string?>(
            "SELECT Value FROM Settings WHERE Key = @key",
            new { key = GetReadingSettingsHandler.BookPageMinutesKey });
        var mangaVal = await conn.ExecuteScalarAsync<string?>(
            "SELECT Value FROM Settings WHERE Key = @key",
            new { key = GetReadingSettingsHandler.MangaChapterMinutesKey });

        var bookMinutes = double.TryParse(bookVal, CultureInfo.InvariantCulture, out var b) && b >= 0.2 && b <= 10.0
            ? b
            : GetReadingSettingsHandler.DefaultBookPageMinutes;

        var mangaMinutes = double.TryParse(mangaVal, CultureInfo.InvariantCulture, out var m) && m >= 0.5 && m <= 30.0
            ? m
            : GetReadingSettingsHandler.DefaultMangaChapterMinutes;

        return (bookMinutes, mangaMinutes);
    }
}

/// <summary>Aggregated stats row from MediaItems.</summary>
public sealed class MediaStatsRow
{
    public long Total { get; set; }
    public int? Completed { get; set; }
    public int? InProgress { get; set; }
    public int? Planned { get; set; }
    public int? CompletedGames { get; set; }
    public int? CompletedBooks { get; set; }
    public int? CompletedMovies { get; set; }
    public double? TotalHoursPlayed { get; set; }
    public int? TotalPagesRead { get; set; }
    public int? TotalChaptersRead { get; set; }
}
