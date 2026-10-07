using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

public interface IGetMediaStatsHandler
{
    Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct);
    Task<Result<AdvancedStatsDto>> HandleAdvancedAsync(CancellationToken ct);
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

    public async Task<Result<AdvancedStatsDto>> HandleAdvancedAsync(CancellationToken ct)
    {
        if (cache.TryGetValue(AdvancedStatsCalculator.CacheKey, out AdvancedStatsDto? cached) && cached is not null)
        {
            return Result<AdvancedStatsDto>.Success(cached);
        }

        var items = await MediaItemGraph
            .LoadNoTracking(db)
            .ToListAsync(ct);

        var stats = AdvancedStatsCalculator.Calculate(items);
        cache.Set(AdvancedStatsCalculator.CacheKey, stats, TimeSpan.FromMinutes(5));

        return Result<AdvancedStatsDto>.Success(stats);
    }
}
