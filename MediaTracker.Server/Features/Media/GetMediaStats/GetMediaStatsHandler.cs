using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>The dashboard counters, kept in its own slice because it is its own read shape.</summary>
public interface IGetMediaStatsHandler
{
    Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct);
}

public sealed class GetMediaStatsHandler(AppDbContext db) : IGetMediaStatsHandler
{
    private const string Discriminator = "MediaType";

    public async Task<Result<MediaStatsDto>> HandleAsync(CancellationToken ct)
    {
        // One grouped scan over MediaItems yields every per-type count and sum the dashboard shows,
        // instead of the five separate round-trips this endpoint used to issue.
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
}
