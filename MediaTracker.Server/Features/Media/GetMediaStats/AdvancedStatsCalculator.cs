using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

public static class AdvancedStatsCalculator
{
    public const string CacheKey = "stats:advanced";

    public static AdvancedStatsDto Calculate(IReadOnlyCollection<MediaItem> items, DateTime? now = null)
    {
        var refTime = now ?? DateTime.UtcNow;

        var totalTitles = items.Count;
        var completedTitles = items.Count(x => x.Status == MediaStatus.Completed);
        var completionRate = totalTitles > 0
            ? Math.Round((double)completedTitles / totalTitles * 100.0, 1, MidpointRounding.AwayFromZero)
            : 0.0;

        double gameHours = 0;
        foreach (var game in items.OfType<VideoGame>())
        {
            gameHours += game.HoursPlayed ?? 0;
        }

        double movieHours = 0;
        foreach (var movie in items.OfType<Movie>())
        {
            var duration = movie.DurationMinutes > 0 ? movie.DurationMinutes : 90;
            movieHours += duration / 60.0;
        }

        double seriesHours = 0;
        double animeHours = 0;
        var totalEpisodesWatched = 0;

        foreach (var show in items.OfType<TvShow>())
        {
            var episodesWatched = show.TotalEpisodesWatched;
            totalEpisodesWatched += episodesWatched;

            if (show.IsAnime)
            {
                var duration = show.EpisodeDurationMinutes is > 0 ? show.EpisodeDurationMinutes.Value : 24;
                animeHours += (episodesWatched * duration) / 60.0;
            }
            else
            {
                var duration = show.EpisodeDurationMinutes is > 0 ? show.EpisodeDurationMinutes.Value : 45;
                seriesHours += (episodesWatched * duration) / 60.0;
            }
        }

        double bookHours = 0;
        var totalPagesRead = 0;
        foreach (var book in items.OfType<Book>())
        {
            totalPagesRead += book.CurrentPage;
            bookHours += (book.CurrentPage * 1.5) / 60.0;
        }

        double mangaHours = 0;
        var totalChaptersRead = 0;
        foreach (var manga in items.OfType<Manga>())
        {
            totalChaptersRead += manga.CurrentChapter;
            mangaHours += (manga.CurrentChapter * 6.0) / 60.0;
        }

        var totalHours = gameHours + movieHours + seriesHours + animeHours + bookHours + mangaHours;
        var totalDays = totalHours / 24.0;

        var scoreDistribution = new Dictionary<int, int>();
        for (var i = 1; i <= 10; i++)
        {
            scoreDistribution[i] = 0;
        }

        var scoredItems = new List<(MediaItem Item, int Score)>();
        foreach (var item in items)
        {
            if (item.Score is >= 1 and <= 10)
            {
                scoreDistribution[item.Score.Value]++;
                scoredItems.Add((item, item.Score.Value));
            }
        }

        var averageScore = scoredItems.Count > 0
            ? Math.Round(scoredItems.Average(x => x.Score), 1, MidpointRounding.AwayFromZero)
            : 0.0;

        var averageScoreByType = scoredItems
            .GroupBy(x => GetMediaTypeName(x.Item))
            .ToDictionary(
                g => g.Key,
                g => Math.Round(g.Average(x => x.Score), 1, MidpointRounding.AwayFromZero));

        var activeDates = new HashSet<DateOnly>();
        foreach (var item in items)
        {
            if (item.FinishedAt is { } finishedAt)
            {
                activeDates.Add(DateOnly.FromDateTime(finishedAt));
            }

            if (item.UpdatedAt != default)
            {
                activeDates.Add(DateOnly.FromDateTime(item.UpdatedAt));
            }
        }

        var todayUtc = DateOnly.FromDateTime(refTime);
        var todayLocal = DateOnly.FromDateTime(DateTime.Now);

        DateOnly startCheckDate;
        if (activeDates.Contains(todayLocal))
        {
            startCheckDate = todayLocal;
        }
        else if (activeDates.Contains(todayUtc))
        {
            startCheckDate = todayUtc;
        }
        else if (activeDates.Contains(todayLocal.AddDays(-1)))
        {
            startCheckDate = todayLocal.AddDays(-1);
        }
        else if (activeDates.Contains(todayUtc.AddDays(-1)))
        {
            startCheckDate = todayUtc.AddDays(-1);
        }
        else
        {
            startCheckDate = default;
        }

        var currentStreakDays = 0;
        if (startCheckDate != default)
        {
            var cursor = startCheckDate;
            while (activeDates.Contains(cursor))
            {
                currentStreakDays++;
                cursor = cursor.AddDays(-1);
            }
        }

        var monthlyDict = new Dictionary<string, int>();
        for (var i = 11; i >= 0; i--)
        {
            var monthDate = refTime.AddMonths(-i);
            var key = monthDate.ToString("yyyy-MM", CultureInfo.InvariantCulture);
            monthlyDict[key] = 0;
        }

        foreach (var item in items)
        {
            if (item.FinishedAt is { } finishedAt)
            {
                var key = finishedAt.ToString("yyyy-MM", CultureInfo.InvariantCulture);
                if (monthlyDict.ContainsKey(key))
                {
                    monthlyDict[key]++;
                }
            }
        }

        var monthlyCompletions = monthlyDict
            .Select(kv => new MonthlyActivityDto(kv.Key, kv.Value))
            .ToList();

        var genreCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var totalGenreOccurrences = 0;

        foreach (var item in items)
        {
            if (string.IsNullOrWhiteSpace(item.Genres))
            {
                continue;
            }

            var genres = item.Genres.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            foreach (var genre in genres)
            {
                if (string.IsNullOrWhiteSpace(genre))
                {
                    continue;
                }

                genreCounts[genre] = genreCounts.GetValueOrDefault(genre) + 1;
                totalGenreOccurrences++;
            }
        }

        var topGenres = genreCounts
            .OrderByDescending(kv => kv.Value)
            .ThenBy(kv => kv.Key)
            .Take(10)
            .Select(kv => new GenreStatDto(
                kv.Key,
                kv.Value,
                totalGenreOccurrences > 0 ? Math.Round((double)kv.Value / totalGenreOccurrences * 100.0, 1, MidpointRounding.AwayFromZero) : 0.0))
            .ToList();

        return new AdvancedStatsDto
        {
            TotalTitles = totalTitles,
            CompletedTitles = completedTitles,
            CompletionRatePercent = completionRate,
            TotalHours = Math.Round(totalHours, 1, MidpointRounding.AwayFromZero),
            TotalDays = Math.Round(totalDays, 1, MidpointRounding.AwayFromZero),
            GameHours = Math.Round(gameHours, 1, MidpointRounding.AwayFromZero),
            MovieHours = Math.Round(movieHours, 1, MidpointRounding.AwayFromZero),
            SeriesHours = Math.Round(seriesHours, 1, MidpointRounding.AwayFromZero),
            AnimeHours = Math.Round(animeHours, 1, MidpointRounding.AwayFromZero),
            BookHours = Math.Round(bookHours, 1, MidpointRounding.AwayFromZero),
            MangaHours = Math.Round(mangaHours, 1, MidpointRounding.AwayFromZero),
            TotalPagesRead = totalPagesRead,
            TotalChaptersRead = totalChaptersRead,
            TotalEpisodesWatched = totalEpisodesWatched,
            AverageScore = averageScore,
            ScoreDistribution = scoreDistribution,
            AverageScoreByType = averageScoreByType,
            CurrentStreakDays = currentStreakDays,
            MonthlyCompletions = monthlyCompletions,
            TopGenres = topGenres,
        };
    }

    private static string GetMediaTypeName(MediaItem item) => item switch
    {
        VideoGame => "game",
        Book => "book",
        Manga => "manga",
        Movie movie => movie.IsAnime ? "anime" : "movie",
        TvShow show => show.IsAnime ? "anime" : "series",
        _ => "other",
    };
}
