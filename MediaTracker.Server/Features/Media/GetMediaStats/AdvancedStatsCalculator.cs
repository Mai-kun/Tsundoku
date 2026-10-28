using System.Globalization;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

public static class AdvancedStatsCalculator
{
    public const string CacheKey = "stats:advanced";
    public const string CacheKeyCompleted = "stats:advanced:completed";
    public const string CacheKeyAll = "stats:advanced:all";

    public static void InvalidateCache(Microsoft.Extensions.Caching.Memory.IMemoryCache? cache)
    {
        if (cache is null) return;
        cache.Remove(CacheKey);
        cache.Remove(CacheKeyCompleted);
        cache.Remove(CacheKeyAll);
    }

    public static AdvancedStatsDto Calculate(
        IReadOnlyCollection<MediaItem> items,
        DateTime? now = null,
        IEnumerable<MediaEvent>? events = null,
        double bookPageMinutes = 1.5,
        double mangaChapterMinutes = 6.0,
        bool onlyCompleted = true)
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
            // A planned game carries no real playtime, so it stays out even in the "all" scope;
            // progress-driven media (book pages, manga chapters) keep counting there.
            var isEligible = onlyCompleted
                ? game.Status == MediaStatus.Completed
                : game.Status != MediaStatus.Planned;

            if (isEligible)
            {
                gameHours += game.HoursPlayed ?? 0;
            }
        }

        double movieHours = 0;
        double animeMovieHours = 0;
        foreach (var movie in items.OfType<Movie>())
        {
            var duration = 0;
            if (onlyCompleted)
            {
                if (movie.Status == MediaStatus.Completed)
                {
                    duration = movie.DurationMinutes > 0 ? movie.DurationMinutes : 90;
                }
            }
            else if (movie.Status != MediaStatus.Planned)
            {
                duration = movie.DurationMinutes > 0
                    ? movie.DurationMinutes
                    : (movie.Status == MediaStatus.Completed ? 90 : 0);
            }

            if (duration > 0)
            {
                if (movie.IsAnime)
                {
                    animeMovieHours += duration / 60.0;
                }
                else
                {
                    movieHours += duration / 60.0;
                }
            }
        }

        double seriesHours = 0;
        double animeHours = animeMovieHours;
        var seriesEpisodesWatched = 0;
        var animeEpisodesWatched = 0;

        foreach (var show in items.OfType<TvShow>())
        {
            var isEligible = onlyCompleted
                ? show.Status == MediaStatus.Completed

                : true;

            if (!isEligible)
            {
                continue;
            }

            var episodesWatched = show.TotalEpisodesWatched;
            if (show.Status == MediaStatus.Completed && episodesWatched == 0)
            {
                episodesWatched = show.TotalEpisodesCount;
            }

            if (show.IsAnime)
            {
                animeEpisodesWatched += episodesWatched;
                var duration = show.EpisodeDurationMinutes is > 0 ? show.EpisodeDurationMinutes.Value : 24;
                animeHours += (episodesWatched * duration) / 60.0;
            }
            else
            {
                seriesEpisodesWatched += episodesWatched;
                var duration = show.EpisodeDurationMinutes is > 0 ? show.EpisodeDurationMinutes.Value : 45;
                seriesHours += (episodesWatched * duration) / 60.0;
            }
        }

        var totalEpisodesWatched = seriesEpisodesWatched + animeEpisodesWatched;

        double bookHours = 0;
        var totalPagesRead = 0;
        foreach (var book in items.OfType<Book>())
        {
            var isEligible = onlyCompleted
                ? book.Status == MediaStatus.Completed

                : true;

            if (!isEligible)
            {
                continue;
            }

            var pagesRead = book.Status == MediaStatus.Completed
                ? book.TotalPages > 0
                    ? book.TotalPages
                    : book.CurrentPage > 0 ? book.CurrentPage : 300
                : book.CurrentPage;
            totalPagesRead += pagesRead;
            bookHours += (pagesRead * bookPageMinutes) / 60.0;
        }

        double mangaHours = 0;
        var totalChaptersRead = 0;
        foreach (var manga in items.OfType<Manga>())
        {
            var isEligible = onlyCompleted
                ? manga.Status == MediaStatus.Completed

                : true;

            if (!isEligible)
            {
                continue;
            }

            if (manga.Status == MediaStatus.Completed)
            {
                var chapters = manga.TotalChapters is > 0
                    ? manga.TotalChapters.Value
                    : manga.CurrentChapter > 0 ? manga.CurrentChapter : 0;
                totalChaptersRead += chapters;
                mangaHours += manga.TotalChapters is > 0
                    ? (manga.TotalChapters.Value * mangaChapterMinutes) / 60.0
                    : manga.TotalVolumes is > 0
                        ? (manga.TotalVolumes.Value * 50.0) / 60.0
                        : chapters > 0
                            ? (chapters * mangaChapterMinutes) / 60.0
                            : 0;
            }
            else
            {
                totalChaptersRead += manga.CurrentChapter;
                if (manga.CurrentChapter > 0)
                {
                    mangaHours += (manga.CurrentChapter * mangaChapterMinutes) / 60.0;
                }
                else if (manga.CurrentVolume > 0)
                {
                    mangaHours += (manga.CurrentVolume * 50.0) / 60.0;
                }
            }
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
            var isEligible = onlyCompleted
                ? item.Status == MediaStatus.Completed

                : true;

            if (isEligible && item.Score is >= 1 and <= 10)
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
        // Derive local today from refTime, not DateTime.Now: the wall clock would leak real time into
        // an otherwise pure calculation and break the streak walk whenever now != today.
        var todayLocal = DateOnly.FromDateTime(refTime.ToLocalTime());

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
            var isEligible = onlyCompleted
                ? item.Status == MediaStatus.Completed

                : true;

            if (!isEligible || string.IsNullOrWhiteSpace(item.Genres))
            {
                continue;
            }

            foreach (var genre in GenreNormalizer.ExtractGenres(item.Genres))
            {
                var normalized = GenreNormalizer.Normalize(genre);
                if (string.IsNullOrWhiteSpace(normalized))
                {
                    continue;
                }

                genreCounts[normalized] = genreCounts.GetValueOrDefault(normalized) + 1;
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

        var genreCountsByType = new Dictionary<string, Dictionary<string, int>>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in items)
        {
            var isEligible = onlyCompleted
                ? item.Status == MediaStatus.Completed

                : true;

            if (!isEligible || string.IsNullOrWhiteSpace(item.Genres))
            {
                continue;
            }

            var type = GetMediaTypeName(item);
            if (!genreCountsByType.TryGetValue(type, out var counts))
            {
                counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                genreCountsByType[type] = counts;
            }

            foreach (var genre in GenreNormalizer.ExtractGenres(item.Genres))
            {
                var normalized = GenreNormalizer.Normalize(genre);
                if (!string.IsNullOrWhiteSpace(normalized))
                {
                    counts[normalized] = counts.GetValueOrDefault(normalized) + 1;
                }
            }
        }

        var topGenresByType = new Dictionary<string, List<GenreStatDto>>(StringComparer.OrdinalIgnoreCase)
        {
            ["all"] = topGenres,
        };
        foreach (var type in new[] { "game", "movie", "series", "anime", "manga", "book" })
        {
            var counts = genreCountsByType.GetValueOrDefault(type) ?? new Dictionary<string, int>();
            var totalOccurrences = counts.Values.Sum();
            topGenresByType[type] = counts
                .OrderByDescending(kv => kv.Value)
                .ThenBy(kv => kv.Key)
                .Take(10)
                .Select(kv => new GenreStatDto(
                    kv.Key,
                    kv.Value,
                    totalOccurrences > 0 ? Math.Round((double)kv.Value / totalOccurrences * 100.0, 1, MidpointRounding.AwayFromZero) : 0.0))
                .ToList();
        }

        var dailyActivity = new Dictionary<DateOnly, int>();
        var activityStart = DateOnly.FromDateTime(refTime).AddDays(-364);
        var activityEnd = DateOnly.FromDateTime(refTime);
        foreach (var mediaEvent in events ?? [])
        {
            var date = DateOnly.FromDateTime(mediaEvent.CreatedAt);
            if (date >= activityStart && date <= activityEnd)
            {
                dailyActivity[date] = dailyActivity.GetValueOrDefault(date) + 1;
            }
        }

        var finishActivity = items
            .Where(item => item.Status == MediaStatus.Completed && item.FinishedAt.HasValue)
            .GroupBy(item => DateOnly.FromDateTime(item.FinishedAt!.Value));
        foreach (var day in finishActivity)
        {
            if (day.Key >= activityStart && day.Key <= activityEnd && !dailyActivity.ContainsKey(day.Key))
            {
                dailyActivity[day.Key] = day.Count();
            }
        }

        var dailyActivityDto = dailyActivity.ToDictionary(
            kv => kv.Key.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            kv => kv.Value);

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
            SeriesEpisodesWatched = seriesEpisodesWatched,
            AnimeEpisodesWatched = animeEpisodesWatched,
            AverageScore = averageScore,
            ScoreDistribution = scoreDistribution,
            AverageScoreByType = averageScoreByType,
            CurrentStreakDays = currentStreakDays,
            MonthlyCompletions = monthlyCompletions,
            TopGenres = topGenres,
            TopGenresByType = topGenresByType,
            DailyActivity = dailyActivityDto,
        };
    }

    internal static string GetMediaTypeName(MediaItem item) => item switch
    {
        VideoGame => "game",
        Book => "book",
        Manga => "manga",
        Movie movie => movie.IsAnime ? "anime" : "movie",
        TvShow show => show.IsAnime ? "anime" : "series",
        _ => "other",
    };
}
