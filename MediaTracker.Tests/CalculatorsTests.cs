using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Xunit;

namespace MediaTracker.Tests;

public class CalculatorsTests
{
    [Fact]
    public void AdvancedStatsCalculator_ShouldCalculateHoursEpisodesPagesAndStreak()
    {
        var now = new DateTime(2026, 10, 7, 12, 0, 0, DateTimeKind.Utc);

        var game = new VideoGame
        {
            Title = "Game 1",
            Platform = "PC",
            HoursPlayed = 20,
            Score = 8,
            Status = MediaStatus.Completed,
            FinishedAt = now.AddDays(-1),
            UpdatedAt = now.AddDays(-1),
            Genres = "Action, RPG",
        };

        var plannedGame = new VideoGame
        {
            Title = "Planned Game",
            Platform = "PC",
            HoursPlayed = 12,
            Status = MediaStatus.Planned,
        };

        var movie = new Movie
        {
            Title = "Movie 1",
            DurationMinutes = 120,
            Score = 9,
            Status = MediaStatus.Completed,
            FinishedAt = now,
            UpdatedAt = now,
            Genres = "Drama, Sci-Fi",
        };

        var show = new TvShow
        {
            Title = "Show 1",
            IsAnime = false,
            EpisodeDurationMinutes = 60,
            Score = 7,
            Status = MediaStatus.InProgress,
            UpdatedAt = now,
            Genres = "Drama, Crime",
            Seasons =
            [
                new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 10, TotalEpisodes = 10 }
            ],
        };

        var anime = new TvShow
        {
            Title = "Anime 1",
            IsAnime = true,
            EpisodeDurationMinutes = 24,
            Score = 9,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-1),
            Genres = "Anime, Action",
            Seasons =
            [
                new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 5, TotalEpisodes = 12 }
            ],
        };

        var book = new Book
        {
            Title = "Book 1",
            Author = "Author 1",
            CurrentPage = 200,
            TotalPages = 400,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-2),
            Genres = "Fantasy",
        };

        var manga = new Manga
        {
            Title = "Manga 1",
            CurrentChapter = 50,
            TotalChapters = 100,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-3),
            Genres = "Action",
        };

        var items = new MediaItem[] { game, plannedGame, movie, show, anime, book, manga };

        // Test with onlyCompleted = false
        var allStats = AdvancedStatsCalculator.Calculate(items, now, onlyCompleted: false);
        allStats.TotalTitles.Should().Be(7);
        allStats.CompletedTitles.Should().Be(2);
        allStats.GameHours.Should().Be(20.0);
        allStats.MovieHours.Should().Be(2.0);
        allStats.SeriesHours.Should().Be(10.0);
        allStats.AnimeHours.Should().Be(2.0);
        allStats.BookHours.Should().Be(5.0); // 200 pages * 1.5 min = 300 min = 5 hours
        allStats.MangaHours.Should().Be(5.0); // 50 chapters * 6 min = 300 min = 5 hours
        allStats.TotalHours.Should().Be(44.0);
        allStats.TotalPagesRead.Should().Be(200);
        allStats.TotalChaptersRead.Should().Be(50);
        allStats.TotalEpisodesWatched.Should().Be(15);
        allStats.SeriesEpisodesWatched.Should().Be(10);
        allStats.AnimeEpisodesWatched.Should().Be(5);

        // Activity streak test: items active on today (now), now - 1 day, now - 2 days, now - 3 days -> 4 consecutive days
        allStats.CurrentStreakDays.Should().Be(4);

        // Test with onlyCompleted = true
        var completedStats = AdvancedStatsCalculator.Calculate(items, now, onlyCompleted: true);
        completedStats.TotalTitles.Should().Be(7);
        completedStats.CompletedTitles.Should().Be(2);
        completedStats.GameHours.Should().Be(20.0);
        completedStats.MovieHours.Should().Be(2.0);
        completedStats.SeriesHours.Should().Be(0.0);
        completedStats.TotalHours.Should().Be(22.0);
    }

    [Fact]
    public void TasteProfileCalculator_ShouldClassifyArchetypesCorrectly()
    {
        var now = new DateTime(2026, 10, 7, 12, 0, 0, DateTimeKind.Utc);

        // 1. Critic archetype: scoredCount >= 10, averageScore <= 6.5
        var criticItems = new List<MediaItem>();
        for (var i = 0; i < 10; i++)
        {
            criticItems.Add(new Movie { Title = $"Movie {i}", Status = MediaStatus.Completed, Score = 5, DurationMinutes = 90 });
        }
        var criticStats = AdvancedStatsCalculator.Calculate(criticItems, now, onlyCompleted: true);
        var criticProfile = TasteProfileCalculator.Calculate(criticItems, criticStats, onlyCompleted: true);
        criticProfile.Persona.Icon.Should().Be("critic");

        // 2. Enthusiast archetype: scoredCount >= 10, averageScore >= 8.5
        var enthusiastItems = new List<MediaItem>();
        for (var i = 0; i < 10; i++)
        {
            enthusiastItems.Add(new Movie { Title = $"Movie {i}", Status = MediaStatus.Completed, Score = 9, DurationMinutes = 90 });
        }
        var enthusiastStats = AdvancedStatsCalculator.Calculate(enthusiastItems, now, onlyCompleted: true);
        var enthusiastProfile = TasteProfileCalculator.Calculate(enthusiastItems, enthusiastStats, onlyCompleted: true);
        enthusiastProfile.Persona.Icon.Should().Be("enthusiast");

        // 3. Perfectionist archetype: total >= 20, completionRate >= 80%
        var perfectionistItems = new List<MediaItem>();
        for (var i = 0; i < 20; i++)
        {
            perfectionistItems.Add(new Movie
            {
                Title = $"Movie {i}",
                Status = i < 18 ? MediaStatus.Completed : MediaStatus.InProgress,
                Score = 7,
                DurationMinutes = 90
            });
        }
        var perfectionistStats = AdvancedStatsCalculator.Calculate(perfectionistItems, now, onlyCompleted: false);
        var perfectionistProfile = TasteProfileCalculator.Calculate(perfectionistItems, perfectionistStats, onlyCompleted: false);
        perfectionistProfile.Persona.Icon.Should().Be("perfectionist");

        // 4. Tsundoku Master archetype: total >= 50, completionRate <= 25%
        var tsundokuItems = new List<MediaItem>();
        for (var i = 0; i < 50; i++)
        {
            tsundokuItems.Add(new Movie
            {
                Title = $"Planned Movie {i}",
                Status = i < 5 ? MediaStatus.Completed : MediaStatus.Planned,
                Score = 7,
                DurationMinutes = 90
            });
        }
        var tsundokuStats = AdvancedStatsCalculator.Calculate(tsundokuItems, now, onlyCompleted: false);
        var tsundokuProfile = TasteProfileCalculator.Calculate(tsundokuItems, tsundokuStats, onlyCompleted: false);
        tsundokuProfile.Persona.Icon.Should().Be("tsundoku_master");
    }

    [Fact]
    public void TasteProfileCalculator_ShouldCalculateSunkCostAndDivergence()
    {
        var now = new DateTime(2026, 10, 7, 12, 0, 0, DateTimeKind.Utc);

        var droppedGame = new VideoGame
        {
            Title = "Dropped Game",
            Platform = "PC",
            HoursPlayed = 30,
            Score = 3,
            Status = MediaStatus.Dropped,
            Genres = "Action",
        };

        var lowScoreBook = new Book
        {
            Title = "Low Score Book",
            Author = "Author 1",
            CurrentPage = 120,
            Score = 4,
            Status = MediaStatus.InProgress,
            Genres = "Fantasy",
            ReleaseYear = 1995,
        };

        var gemMovie = new Movie
        {
            Title = "Hidden Gem",
            DurationMinutes = 120,
            Score = 9,
            ExternalRating = 6.8,
            Status = MediaStatus.Completed,
            Genres = "Sci-Fi",
            ReleaseYear = 2015,
        };

        var disappointmentMovie = new Movie
        {
            Title = "Disappointment",
            DurationMinutes = 90,
            Score = 4,
            ExternalRating = 9.5,
            Status = MediaStatus.Completed,
            Genres = "Drama",
            ReleaseYear = 2023,
        };

        var items = new MediaItem[] { droppedGame, lowScoreBook, gemMovie, disappointmentMovie };
        var stats = AdvancedStatsCalculator.Calculate(items, now, onlyCompleted: false);
        var profile = TasteProfileCalculator.Calculate(items, stats, onlyCompleted: false);

        // Sunk Cost calculation:
        // droppedGame (30 h) + lowScoreBook (120 pages * 1.5 min = 3 h) + disappointmentMovie (90 min = 1.5 h) = 34.5 hours
        profile.SunkCost.LowScoreHours.Should().Be(34.5);
        profile.SunkCost.TitlesCount.Should().Be(3);
        profile.SunkCost.CategoryBreakdown["game"].Should().Be(30.0);
        profile.SunkCost.CategoryBreakdown["book"].Should().Be(3.0);
        profile.SunkCost.CategoryBreakdown["movie"].Should().Be(1.5);

        // Divergence calculation:
        // Gem: user 9.0 vs world 6.8 -> delta +2.2
        profile.Divergence.HiddenGem.Should().NotBeNull();
        profile.Divergence.HiddenGem!.Title.Should().Be("Hidden Gem");
        profile.Divergence.HiddenGem.Delta.Should().Be(2.2);

        // Disappointment: world 9.5 vs user 4.0 -> delta -5.5
        profile.Divergence.Disappointment.Should().NotBeNull();
        profile.Divergence.Disappointment!.Title.Should().Be("Disappointment");
        profile.Divergence.Disappointment.Delta.Should().Be(-5.5);
    }

    [Fact]
    public void SmartListEvaluator_ShouldFilterByCategoriesStatusesYearAuthorAndLimit()
    {
        var anime = new TvShow { Title = "Attack on Titan", IsAnime = true, ReleaseYear = 2013, Status = MediaStatus.Completed, Score = 9 };
        var movie = new Movie { Title = "Inception", DurationMinutes = 148, Score = 9, ReleaseYear = 2010, Status = MediaStatus.Completed, Studio = "Syncopy" };
        var shortMovie = new Movie { Title = "Short Film", DurationMinutes = 40, Score = 6, ReleaseYear = 2020, Status = MediaStatus.Planned, Studio = "Studio Ghibli" };
        var book = new Book { Title = "The Hobbit", Author = "J.R.R. Tolkien", TotalPages = 310, ReleaseYear = 1937, Status = MediaStatus.InProgress, Score = 8 };

        var items = new List<MediaItem> { anime, movie, shortMovie, book };

        // Category filter
        var animeList = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Categories = ["anime"] });
        animeList.Should().ContainSingle().Which.Title.Should().Be("Attack on Titan");

        // Status filter
        var completedList = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Statuses = [MediaStatus.Completed] });
        completedList.Should().HaveCount(2).And.Contain(anime).And.Contain(movie);

        // Year filter
        var modernList = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { ReleaseYearFrom = 2010, ReleaseYearTo = 2015 });
        modernList.Should().HaveCount(2).And.Contain(anime).And.Contain(movie);

        // Author/Creator filter
        var tolkienList = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { CreatorContains = "Tolkien" });
        tolkienList.Should().ContainSingle().Which.Title.Should().Be("The Hobbit");

        // Limit filter
        var limitedList = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Limit = 2 });
        limitedList.Should().HaveCount(2);
    }

    [Fact]
    public void ImportMatchScorer_ShouldScoreAndEvaluateCandidatesAccurately()
    {
        var manga = new Manga
        {
            Title = "Гачиакута",
            RomajiTitle = "Gachiakuta",
            Author = "Kei Urana",
            ReleaseYear = 2025,
            TotalChapters = 40,
        };

        var exactCandidate = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Gachiakuta",
            RomajiTitle = "Gachiakuta",
            ReleaseYear = 2025,
            Author = "Kei Urana",
            Chapters = 40,
            Type = "manga",
        };

        var divergentCandidate = new ExternalMediaDto
        {
            ExternalId = "2",
            Title = "Gachiakuta: Spin-off",
            ReleaseYear = 2020,
            Author = "Another Author",
            Chapters = 10,
            Type = "manga",
        };

        // Score exact candidate -> should be high (>= 75)
        var exactScore = ImportMatchScorer.ScoreCandidate(manga, exactCandidate);
        exactScore.Should().BeGreaterThanOrEqualTo(75);

        // Score divergent candidate -> should be lower
        var divergentScore = ImportMatchScorer.ScoreCandidate(manga, divergentCandidate);
        divergentScore.Should().BeLessThan(exactScore);

        // Evaluate with clear winner -> Confident
        var confidentVerdict = ImportMatchScorer.EvaluateCandidates(manga, [exactCandidate, divergentCandidate]);
        confidentVerdict.Kind.Should().Be(MatchVerdictKind.Confident);
        confidentVerdict.Winner?.Title.Should().Be("Gachiakuta");

        // Two close candidates -> Ambiguous
        var closeCandidate1 = new ExternalMediaDto { ExternalId = "3", Title = "Sword Art Online: Progressive", ReleaseYear = 2016, Type = "manga" };
        var closeCandidate2 = new ExternalMediaDto { ExternalId = "4", Title = "Sword Art Online: Girls Ops", ReleaseYear = 2016, Type = "manga" };
        var ambiguousVerdict = ImportMatchScorer.EvaluateCandidates(
            new Manga { Title = "Sword Art Online", RomajiTitle = "Sword Art Online", ReleaseYear = 2016 },
            [closeCandidate1, closeCandidate2]);
        ambiguousVerdict.Kind.Should().Be(MatchVerdictKind.Ambiguous);
        ambiguousVerdict.Candidates.Should().HaveCount(2);

        // No candidates -> NoMatch
        var noMatchVerdict = ImportMatchScorer.EvaluateCandidates(manga, []);
        noMatchVerdict.Kind.Should().Be(MatchVerdictKind.NoMatch);
    }
}
