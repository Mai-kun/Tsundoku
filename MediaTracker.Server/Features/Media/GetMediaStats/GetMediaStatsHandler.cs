using System.Globalization;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
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
    private const string Discriminator = "MediaType";

    public async Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct)
    {
        var totals = await db.MediaItems
            .AsNoTracking()
            .GroupBy(_ => 1)
            .Select(g => new
            {
                Total = g.Count(),
                Completed = g.Sum(x => x.Status == MediaStatus.Completed ? 1 : 0),
                InProgress = g.Sum(x => x.Status == MediaStatus.InProgress ? 1 : 0),
                Planned = g.Sum(x => x.Status == MediaStatus.Planned ? 1 : 0),
                CompletedGames = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Game" ? 1 : 0),
                CompletedBooks = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Book" ? 1 : 0),
                CompletedMovies = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Movie" ? 1 : 0),
                TotalHoursPlayed = g.Sum(x => x is VideoGame ? ((VideoGame)x).HoursPlayed ?? 0 : 0),
                TotalPagesRead = g.Sum(x => x is Book ? ((Book)x).CurrentPage : 0),
                TotalChaptersRead = g.Sum(x => x is Manga ? ((Manga)x).CurrentChapter : 0),
            })
            .FirstOrDefaultAsync(ct);

        var totalEpisodesWatched = await db.TvSeasons
            .AsNoTracking()
            .SumAsync(season => season.CurrentEpisode, ct);

        var stats = new MediaStatsDto
        {
            TotalItems = totals?.Total ?? 0,
            CompletedItems = totals?.Completed ?? 0,
            InProgressItems = totals?.InProgress ?? 0,
            PlannedItems = totals?.Planned ?? 0,
            CompletedGamesCount = totals?.CompletedGames ?? 0,
            CompletedBooksCount = totals?.CompletedBooks ?? 0,
            CompletedMoviesCount = totals?.CompletedMovies ?? 0,
            TotalHoursPlayed = totals?.TotalHoursPlayed ?? 0,
            TotalPagesRead = totals?.TotalPagesRead ?? 0,
            TotalChaptersRead = totals?.TotalChaptersRead ?? 0,
            TotalEpisodesWatched = totalEpisodesWatched,
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

        var items = await MediaItemGraph
            .LoadNoTracking(db)
            .ToListAsync(ct);

        var activityStart = DateTime.UtcNow.AddDays(-364);
        var events = await db.Events
            .AsNoTracking()
            .Where(mediaEvent => mediaEvent.CreatedAt >= activityStart)
            .ToListAsync(ct);

        var (bookMinutes, mangaMinutes) = await ReadReadingMinutesAsync(ct);

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

        var items = await MediaItemGraph
            .LoadNoTracking(db)
            .ToListAsync(ct);
        var (bookMinutes, mangaMinutes) = await ReadReadingMinutesAsync(ct);

        var profile = TasteProfileCalculator.Calculate(items, advancedStats.Value!, bookMinutes, mangaMinutes, onlyCompleted: onlyCompleted);
        cache.Set(cacheKey, profile, TimeSpan.FromMinutes(5));

        return Result<TasteProfileDto>.Success(profile);
    }

    private async Task<(double BookMinutes, double MangaMinutes)> ReadReadingMinutesAsync(CancellationToken ct)
    {
        var bookVal = await AppSettingStore.ReadAsync(db, GetReadingSettingsHandler.BookPageMinutesKey, ct);
        var mangaVal = await AppSettingStore.ReadAsync(db, GetReadingSettingsHandler.MangaChapterMinutesKey, ct);

        var bookMinutes = double.TryParse(bookVal, CultureInfo.InvariantCulture, out var b) && b >= 0.2 && b <= 10.0
            ? b
            : GetReadingSettingsHandler.DefaultBookPageMinutes;

        var mangaMinutes = double.TryParse(mangaVal, CultureInfo.InvariantCulture, out var m) && m >= 0.5 && m <= 30.0
            ? m
            : GetReadingSettingsHandler.DefaultMangaChapterMinutes;

        return (bookMinutes, mangaMinutes);
    }
}
