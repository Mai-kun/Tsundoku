using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Covers the branches of TasteProfileCalculator the archetype test in CalculatorsTests misses:
/// sunk-cost hour formulas per media type, divergence filtering, genre paradox fallbacks,
/// era buckets, radar normalization and every remaining persona.
/// </summary>
public class TasteProfileCoverageTests
{
    private static AdvancedStatsDto Stats(
        int totalTitles = 0,
        double totalHours = 0,
        double completionRate = 0,
        double mangaHours = 0,
        int totalChaptersRead = 0,
        double animeHours = 0,
        double gameHours = 0,
        double bookHours = 0,
        int totalPagesRead = 0,
        double movieHours = 0,
        double seriesHours = 0,
        int seriesEpisodesWatched = 0)
        => new()
        {
            TotalTitles = totalTitles,
            TotalHours = totalHours,
            CompletionRatePercent = completionRate,
            MangaHours = mangaHours,
            TotalChaptersRead = totalChaptersRead,
            AnimeHours = animeHours,
            GameHours = gameHours,
            BookHours = bookHours,
            TotalPagesRead = totalPagesRead,
            MovieHours = movieHours,
            SeriesHours = seriesHours,
            SeriesEpisodesWatched = seriesEpisodesWatched,
        };

    private static List<Movie> Movies(string genre, int count, MediaStatus status = MediaStatus.Completed)
        => Enumerable.Range(0, count)
            .Select(i => new Movie { Title = $"{genre} {i}", Status = status, Genres = genre })
            .ToList();

    private static TvShow Show(int watched, int total, bool isAnime = false)
        => new()
        {
            Title = $"Show {Guid.NewGuid():N}",
            IsAnime = isAnime,
            Status = MediaStatus.Completed,
            Seasons = [new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = watched, TotalEpisodes = total }],
        };

    [Fact]
    public void InvalidateCache_ShouldRemoveAllThreeKeys_AndTolerateNullCache()
    {
        var cache = new MemoryCache(new MemoryCacheOptions());
        cache.Set(TasteProfileCalculator.CacheKey, new object());
        cache.Set(TasteProfileCalculator.CacheKeyCompleted, new object());
        cache.Set(TasteProfileCalculator.CacheKeyAll, new object());

        TasteProfileCalculator.InvalidateCache(cache);

        cache.TryGetValue(TasteProfileCalculator.CacheKey, out _).Should().BeFalse();
        cache.TryGetValue(TasteProfileCalculator.CacheKeyCompleted, out _).Should().BeFalse();
        cache.TryGetValue(TasteProfileCalculator.CacheKeyAll, out _).Should().BeFalse();

        // Null cache must be a safe no-op
        TasteProfileCalculator.InvalidateCache(null);
    }

    [Fact]
    public void Calculate_EmptyLibrary_ShouldReturnArchivistAndEmptySections()
    {
        var profile = TasteProfileCalculator.Calculate([], Stats());

        profile.Persona.Icon.Should().Be("archivist");
        profile.SunkCost.LowScoreHours.Should().Be(0);
        profile.SunkCost.PercentageOfTotal.Should().Be(0); // TotalHours == 0 branch
        profile.SunkCost.TitlesCount.Should().Be(0);
        profile.Divergence.HiddenGem.Should().BeNull();
        profile.Divergence.Disappointment.Should().BeNull();
        profile.GenreParadox.Should().BeEmpty();
        profile.EraAffinity.Should().BeEmpty();
        profile.GenreRadar.Should().BeEmpty();
        profile.DropAnalytics.TotalDropped.Should().Be(0);
        profile.DropAnalytics.EarlyDropCount.Should().Be(0);
        profile.DropAnalytics.MidDropCount.Should().Be(0);
        profile.DropAnalytics.LateDropCount.Should().Be(0);
        profile.DropAnalytics.TopReasons.Should().BeEmpty();
    }

    [Fact]
    public void SunkCost_AndAllScope_ShouldSumHoursAcrossEveryMediaType()
    {
        var items = new List<MediaItem>
        {
            // Dropped game without logged hours -> 0h, and the "game" breakdown entry must be filtered out
            new VideoGame { Title = "G dropped", Platform = "PC", Status = MediaStatus.Dropped, Score = 3 },
            // Completed movie without a duration -> 90-minute fallback
            new Movie { Title = "M nodur", Status = MediaStatus.Completed, Score = 1 },
            new Movie { Title = "M 120", Status = MediaStatus.Completed, Score = 4, DurationMinutes = 120 },
            // Completed show: watched episodes from seasons, no episode duration -> 45-minute fallback
            Show(watched: 10, total: 20),
            // Completed show with zero watched episodes -> falls back to the total episode count
            Show(watched: 0, total: 12, isAnime: true),
            // In-progress book -> pages read from CurrentPage
            new Book { Title = "B inprog", Author = "A", Status = MediaStatus.InProgress, Score = 2, CurrentPage = 100 },
            // Completed book -> pages read from TotalPages
            new Book { Title = "B done", Author = "A", Status = MediaStatus.Completed, Score = 1, TotalPages = 400, CurrentPage = 50 },
            // In-progress manga -> chapters from CurrentChapter
            new Manga { Title = "Mg inprog", Status = MediaStatus.InProgress, Score = 3, CurrentChapter = 40 },
            // Completed manga without chapters -> volumes * 50 minutes
            new Manga { Title = "Mg vols", Status = MediaStatus.Completed, Score = 2, TotalVolumes = 6 },
            // Completed manga with neither chapters nor volumes -> 0h
            new Manga { Title = "Mg zero", Status = MediaStatus.Completed, Score = 2 },
            // Planned titles are excluded entirely in both scopes
            new VideoGame { Title = "G planned", Platform = "PC", Status = MediaStatus.Planned, Score = 1 },
            new Manga { Title = "Mg planned", Status = MediaStatus.Planned, Score = 2 },
            new Movie { Title = "M planned", Status = MediaStatus.Planned, Score = 1 },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(totalHours: 69), onlyCompleted: false);

        // 1.5 + 2 + 7.5 (10 eps * 45 min) + 2 (5 eps * 24 min) + 2.5 + 10 + 4 + 5 = 34.5
        profile.SunkCost.LowScoreHours.Should().Be(34.5);
        profile.SunkCost.TitlesCount.Should().Be(10);
        profile.SunkCost.PercentageOfTotal.Should().Be(50.0);
        profile.SunkCost.CategoryBreakdown.Should().NotContainKey("game"); // only a 0-hour game existed
        profile.SunkCost.CategoryBreakdown["movie"].Should().Be(3.5);
        profile.SunkCost.CategoryBreakdown["series"].Should().Be(7.5);
        profile.SunkCost.CategoryBreakdown["anime"].Should().Be(2.0);
        profile.SunkCost.CategoryBreakdown["book"].Should().Be(12.5);
        profile.SunkCost.CategoryBreakdown["manga"].Should().Be(9.0);
    }

    [Fact]
    public void SunkCost_OnlyCompletedScope_ShouldCountGameHoursAndDefaultBookPages()
    {
        var items = new List<MediaItem>
        {
            new VideoGame { Title = "G done", Platform = "PC", Status = MediaStatus.Completed, Score = 4, HoursPlayed = 10 },
            // Non-completed titles are excluded when onlyCompleted = true
            new VideoGame { Title = "G inprog", Platform = "PC", Status = MediaStatus.InProgress, Score = 4, HoursPlayed = 99 },
            new Movie { Title = "M inprog", Status = MediaStatus.InProgress, Score = 5, DurationMinutes = 90 },
            new Movie { Title = "M dropped", Status = MediaStatus.Dropped, Score = 3 },
            // Completed book with no page data -> 300-page default
            new Book { Title = "B nodata", Author = "A", Status = MediaStatus.Completed, Score = 5 },
            // Completed book without a total -> CurrentPage fallback
            new Book { Title = "B cur", Author = "A", Status = MediaStatus.Completed, Score = 5, CurrentPage = 60 },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(totalHours: 38), onlyCompleted: true);

        // 10h game + 7.5h (300 pages) + 1.5h (60 pages) = 19
        profile.SunkCost.LowScoreHours.Should().Be(19.0);
        profile.SunkCost.TitlesCount.Should().Be(3);
        profile.SunkCost.PercentageOfTotal.Should().Be(50.0);
        profile.SunkCost.CategoryBreakdown["game"].Should().Be(10.0);
        profile.SunkCost.CategoryBreakdown["book"].Should().Be(9.0);
    }

    [Fact]
    public void Divergence_ShouldFilterInvalidEntriesAndPickLargestGaps()
    {
        var items = new List<MediaItem>
        {
            // Score outside 1..10, null score, null or zero rating -> all excluded
            new Movie { Title = "Score zero", Status = MediaStatus.Completed, Score = 0, ExternalRating = 9 },
            new Movie { Title = "Score null", Status = MediaStatus.Completed, ExternalRating = 8 },
            new Movie { Title = "Rating null", Status = MediaStatus.Completed, Score = 9 },
            new Movie { Title = "Rating zero", Status = MediaStatus.Completed, Score = 8, ExternalRating = 0 },
            // Planned is never eligible in either scope
            new Movie { Title = "Planned gem", Status = MediaStatus.Planned, Score = 9, ExternalRating = 5 },
            // Eligible in the "all" scope; gem ordered by delta (5 > 4)
            new Movie { Title = "Hold gem", Status = MediaStatus.OnHold, Score = 10, ExternalRating = 5 },
            new Movie { Title = "Progress gem", Status = MediaStatus.InProgress, Score = 9, ExternalRating = 5 },
            // Disappointment: world 9.5 vs user 4
            new Movie { Title = "Flop", Status = MediaStatus.Completed, Score = 4, ExternalRating = 9 },
            // Middle of the road: neither a gem (score < 8) nor a disappointment (score > 5)
            new Movie { Title = "Middle", Status = MediaStatus.Completed, Score = 7, ExternalRating = 8 },
        };

        var allScope = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);
        allScope.Divergence.HiddenGem!.Title.Should().Be("Hold gem");
        allScope.Divergence.HiddenGem.Delta.Should().Be(5.0);
        allScope.Divergence.HiddenGem.Type.Should().Be("movie");
        allScope.Divergence.Disappointment!.Title.Should().Be("Flop");
        allScope.Divergence.Disappointment.Delta.Should().Be(-5.0);

        // With onlyCompleted = true every non-completed candidate drops out
        var completedScope = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: true);
        completedScope.Divergence.HiddenGem.Should().BeNull();
        completedScope.Divergence.Disappointment.Should().BeSameAs(allScope.Divergence.Disappointment);

        // Only moderate scores -> both slots stay empty
        var neutral = new List<MediaItem>
        {
            new Movie { Title = "Middle", Status = MediaStatus.Completed, Score = 7, ExternalRating = 8 },
            new Movie { Title = "Gem-ish", Status = MediaStatus.Completed, Score = 8, ExternalRating = 7.4 }, // world < 7.5: no disappointment
            new Movie { Title = "Meh", Status = MediaStatus.Completed, Score = 6, ExternalRating = 5 },
        };
        var noneScope = TasteProfileCalculator.Calculate(neutral, Stats(), onlyCompleted: false);
        noneScope.Divergence.HiddenGem.Should().BeNull();
        noneScope.Divergence.Disappointment.Should().BeNull();
    }

    [Fact]
    public void GenreParadox_ShouldRankGenresByTrackedCountAndRateThem()
    {
        var items = new List<MediaItem>
        {
            new Movie { Title = "A done", Status = MediaStatus.Completed, Genres = "Action" },
            new Movie { Title = "A dropped", Status = MediaStatus.Dropped, Genres = "Action" },
            new Movie { Title = "A wip", Status = MediaStatus.InProgress, Genres = "Action" },
            new Movie { Title = "D done", Status = MediaStatus.Completed, Genres = "Drama;Drama" }, // duplicate entries dedupe by index? No: two identical entries -> two list entries
            new Movie { Title = "D done 2", Status = MediaStatus.Completed, Genres = "Drama" },
            new Movie { Title = "Solo wip", Status = MediaStatus.InProgress, Genres = "Solo" },
            new Movie { Title = "No genre", Status = MediaStatus.Completed },
            new Movie { Title = "Planned A", Status = MediaStatus.Planned, Genres = "Action" },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);

        profile.GenreParadox.Should().HaveCount(2); // "Solo" (1 tracked) is filtered out
        profile.GenreParadox[0].Genre.Should().Be("Action");
        profile.GenreParadox[0].Total.Should().Be(3);
        profile.GenreParadox[0].Completed.Should().Be(1);
        profile.GenreParadox[0].Dropped.Should().Be(1);
        profile.GenreParadox[0].CompletionRate.Should().Be(33.3);
        profile.GenreParadox[0].DropRate.Should().Be(33.3);
        profile.GenreParadox[1].Genre.Should().Be("Drama");
        profile.GenreParadox[1].CompletionRate.Should().Be(100.0);
        profile.GenreParadox[1].DropRate.Should().Be(0.0);
    }

    [Fact]
    public void GenreParadox_WhenNothingHasTwoItems_ShouldFallBackToRawGenres()
    {
        var items = new List<MediaItem>
        {
            new Movie { Title = "A", Status = MediaStatus.Completed, Genres = "Action" },
            new Movie { Title = "B", Status = MediaStatus.Completed, Genres = "Drama" },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);

        profile.GenreParadox.Should().HaveCount(2);
        profile.GenreParadox.Select(g => g.Genre).Should().Contain(["Action", "Drama"]);
    }

    [Fact]
    public void GenreParadox_ShouldCapAtSixGenres()
    {
        var genres = new[] { "Action", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Romance" };
        var items = genres.SelectMany(g => Movies(g, 2)).ToList();

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);

        profile.GenreParadox.Should().HaveCount(6);
        profile.GenreParadox.Select(g => g.Genre)
            .Should().BeEquivalentTo(["Action", "Comedy", "Drama", "Fantasy", "Horror", "Mystery"], o => o.WithStrictOrdering());
    }

    [Fact]
    public void Genres_ShouldParseJsonArraysAndSplitDelimiters()
    {
        var items = new List<MediaItem>
        {
            // JSON array branch of GenreNormalizer.ExtractGenres
            new Movie { Title = "Json", Status = MediaStatus.Completed, Genres = """["Action", "RPG"]""" },
            // Semicolon/pin split branch
            new Movie { Title = "Csv", Status = MediaStatus.Completed, Genres = "Drama; Sci-Fi;  " },
            // Square-bracket debris cleaned per part
            new Movie { Title = "Brackets", Status = MediaStatus.Completed, Genres = "[Comedy] , [Romance]" },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);

        profile.GenreParadox.Select(g => g.Genre).Should()
            .BeEquivalentTo(["Action", "RPG", "Drama", "Sci-Fi", "Comedy", "Romance"]);
    }

    [Fact]
    public void GenreRadar_ShouldNormalizeVolumeRankSixAndAverageScores()
    {
        var items = new List<MediaItem>
        {
            new Movie { Title = "R1", Status = MediaStatus.Completed, Genres = "Romance", Score = 8 },
            new Movie { Title = "R2", Status = MediaStatus.Completed, Genres = "Romance", Score = 9 },
            new Movie { Title = "C", Status = MediaStatus.Completed, Genres = "Comedy" },                   // no score -> 0 avg
            new Movie { Title = "D", Status = MediaStatus.Completed, Genres = "Drama", Score = 9 },
            new Movie { Title = "F", Status = MediaStatus.Completed, Genres = "Fantasy", Score = 0 },       // 0 is filtered out
            new Movie { Title = "H", Status = MediaStatus.Completed, Genres = "Horror", Score = 7 },
            new Movie { Title = "M", Status = MediaStatus.Completed, Genres = "Mystery", Score = 6 },
            new Movie { Title = "W", Status = MediaStatus.Completed, Genres = "Western", Score = 5 },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: true);

        profile.GenreRadar.Should().HaveCount(6); // Western (alphabetically last) is dropped
        profile.GenreRadar[0].Genre.Should().Be("Romance");
        profile.GenreRadar[0].VolumeScore.Should().Be(100.0);
        profile.GenreRadar[0].AverageScore.Should().Be(8.5);
        profile.GenreRadar.Should().Contain(e => e.Genre == "Comedy" && e.AverageScore == 0.0);
        profile.GenreRadar.Should().Contain(e => e.Genre == "Fantasy" && e.AverageScore == 0.0);
        profile.GenreRadar.Where(e => e.Genre is "Drama" or "Horror" or "Mystery")
            .Should().OnlyContain(e => e.VolumeScore == 50.0);
        profile.GenreRadar.Should().NotContain(e => e.Genre == "Western");
    }

    [Fact]
    public void EraAffinity_ShouldResolveYearsFromEverySourceAndBucketAllDecades()
    {
        var items = new List<MediaItem>
        {
            new Movie { Title = "Y1975", Status = MediaStatus.Completed, ReleaseYear = 1975 },
            new Movie { Title = "Y1983", Status = MediaStatus.Completed, ReleaseYear = 1983 },
            new Movie { Title = "Y1993", Status = MediaStatus.Completed, ReleaseYear = 1993 },
            new Movie { Title = "Y2007", Status = MediaStatus.Completed, ReleaseYear = 2007 },
            new Movie { Title = "Y2012", Status = MediaStatus.Completed, ReleaseYear = 2012 },
            new Movie { Title = "Y2024", Status = MediaStatus.Completed, ReleaseYear = 2024 },
            // Year derived from the release date when ReleaseYear is unset
            new Movie { Title = "D1999", Status = MediaStatus.Completed, ReleaseDate = new DateTime(1999, 5, 1) },
            // Year derived from FinishedAt as the last resort
            new Movie { Title = "F2002", Status = MediaStatus.Completed, FinishedAt = new DateTime(2002, 7, 1) },
            // No year anywhere (CreatedAt = default) -> dropped from the buckets
            new Movie { Title = "NoDate", Status = MediaStatus.Completed, CreatedAt = default },
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: true);

        profile.EraAffinity.Should().HaveCount(6);
        profile.EraAffinity.Select(e => e.Era).Should().ContainInOrder("pre-1980", "1980s", "1990s", "2000s", "2010s", "2020s");
        profile.EraAffinity.Should().Contain(e => e.Era == "1990s" && e.Count == 2 && e.Percentage == 25.0);
        profile.EraAffinity.Should().Contain(e => e.Era == "pre-1980" && e.Count == 1 && e.Percentage == 12.5);
    }

    [Fact]
    public void EraAffinity_AllScope_ShouldUseScoreBasedFavorites()
    {
        var items = new List<MediaItem>
        {
            new Movie { Title = "High wip", Status = MediaStatus.InProgress, Score = 8, ReleaseYear = 2015 }, // qualifies
            new Movie { Title = "Low wip", Status = MediaStatus.InProgress, Score = 7, ReleaseYear = 2015 }, // score < 8
            new Movie { Title = "Planned high", Status = MediaStatus.Planned, Score = 9, ReleaseYear = 2015 }, // planned
            new Movie { Title = "Done low", Status = MediaStatus.Completed, Score = 3, ReleaseYear = 2015 }, // completed always qualifies
        };

        var profile = TasteProfileCalculator.Calculate(items, Stats(), onlyCompleted: false);

        profile.EraAffinity.Should().ContainSingle().Which.Should()
            .Match<EraAffinityStatDto>(e => e.Era == "2010s" && e.Count == 2 && e.Percentage == 100.0);
    }

    // --- Personas not covered by CalculatorsTests ---

    [Fact]
    public void Persona_ShouldDetectMangaDominance_ByHoursChaptersAndCounts()
    {
        // Chapters branch with no hours at all (totalHours == 0 skips the hour disjunct)
        TasteProfileCalculator.Calculate([], Stats(totalChaptersRead: 150), onlyCompleted: true)
            .Persona.Icon.Should().Be("manga_reader");

        // Hours branch: manga > 40% of total
        TasteProfileCalculator.Calculate([], Stats(totalTitles: 10, totalHours: 100, mangaHours: 50), onlyCompleted: true)
            .Persona.Icon.Should().Be("manga_reader");

        // Count branch: at least 15 manga titles and twice the anime count
        var mangas = Enumerable.Range(0, 15).Select(i => new Manga
        {
            Title = $"Mg {i}",
            Status = MediaStatus.Completed,
            Author = "A",
        }).ToList();
        TasteProfileCalculator.Calculate(mangas, Stats(totalTitles: 15), onlyCompleted: true)
            .Persona.Icon.Should().Be("manga_reader");
    }

    [Fact]
    public void Persona_ShouldDetectAnimeGamesBooksMoviesAndSeriesDominance()
    {
        var animeMovies = Enumerable.Range(0, 15)
            .Select(i => new Movie { Title = $"Anime {i}", Status = MediaStatus.Completed, IsAnime = true })
            .ToList();
        TasteProfileCalculator.Calculate(animeMovies, Stats(totalTitles: 19, completionRate: 50, totalHours: 100, animeHours: 50), onlyCompleted: true)
            .Persona.Icon.Should().Be("otaku");

        TasteProfileCalculator.Calculate([], Stats(totalHours: 100, gameHours: 60), onlyCompleted: true)
            .Persona.Icon.Should().Be("gamer");

        TasteProfileCalculator.Calculate([], Stats(totalHours: 100, bookHours: 60), onlyCompleted: true)
            .Persona.Icon.Should().Be("bookworm");

        // TotalPagesRead branch of bookworm: 1000+ pages across 5+ books
        var books = Enumerable.Range(0, 5).Select(i => new Book
        {
            Title = $"B {i}",
            Author = "A",
            Status = MediaStatus.Completed,
        }).ToList();
        TasteProfileCalculator.Calculate(books, Stats(totalTitles: 5, totalHours: 100, totalPagesRead: 1000), onlyCompleted: true)
            .Persona.Icon.Should().Be("bookworm");

        var movies = Enumerable.Range(0, 15)
            .Select(i => new Movie { Title = $"Movie {i}", Status = MediaStatus.Completed })
            .ToList();
        TasteProfileCalculator.Calculate(movies, Stats(totalTitles: 15, completionRate: 50, totalHours: 100, movieHours: 60), onlyCompleted: true)
            .Persona.Icon.Should().Be("cinephile");

        // Episode-count branch of serial binger (SeriesHours zero)
        var shows = Enumerable.Range(0, 5).Select(_ => Show(watched: 12, total: 12)).ToList();
        TasteProfileCalculator.Calculate(shows, Stats(totalTitles: 10, totalHours: 100, seriesEpisodesWatched: 60), onlyCompleted: true)
            .Persona.Icon.Should().Be("serial_binger");

        // SeriesHours branch of serial binger
        TasteProfileCalculator.Calculate(shows, Stats(totalTitles: 10, totalHours: 100, seriesHours: 55), onlyCompleted: true)
            .Persona.Icon.Should().Be("serial_binger");
    }

    [Fact]
    public void Persona_ShouldDetectGenreAtmospheres()
    {
        TasteProfileCalculator.Calculate(Movies("Mystery", 5), Stats(totalTitles: 5), onlyCompleted: true)
            .Persona.Icon.Should().Be("dark_philosopher");

        TasteProfileCalculator.Calculate(Movies("Slice of Life", 5), Stats(totalTitles: 5), onlyCompleted: true)
            .Persona.Icon.Should().Be("cozy_hedonist");

        TasteProfileCalculator.Calculate(Movies("Thriller", 5), Stats(totalTitles: 5), onlyCompleted: true)
            .Persona.Icon.Should().Be("action_junkie");

        TasteProfileCalculator.Calculate(Movies("Cyberpunk", 5), Stats(totalTitles: 5), onlyCompleted: true)
            .Persona.Icon.Should().Be("visionary");

        // Under the 5-occurrence threshold no atmosphere fires
        TasteProfileCalculator.Calculate(Movies("Mystery", 4), Stats(totalTitles: 4), onlyCompleted: true)
            .Persona.Icon.Should().Be("archivist");
    }

    [Fact]
    public void Persona_ShouldDetectOmnivoreAcrossThreeFormats()
    {
        var items = new List<MediaItem>();
        items.AddRange(Enumerable.Range(0, 5).Select(i => new VideoGame { Title = $"G {i}", Platform = "PC", Status = MediaStatus.Completed }));
        items.AddRange(Enumerable.Range(0, 5).Select(i => new Book { Title = $"B {i}", Author = "A", Status = MediaStatus.Completed }));
        items.AddRange(Enumerable.Range(0, 5).Select(i => new Manga { Title = $"Mg {i}", Author = "A", Status = MediaStatus.Completed }));

        var profile = TasteProfileCalculator.Calculate(items, Stats(totalTitles: 15), onlyCompleted: true);

        profile.Persona.Icon.Should().Be("omnivore");
    }

    [Fact]
    public void DropAnalytics_ShouldBucketProgressClampAndRankReasons()
    {
        var items = new List<MediaItem>
        {
            new Book { Title = "B early", Author = "A", Status = MediaStatus.Dropped, DropReason = "Too slow", CurrentPage = 20, TotalPages = 200 },      // 10% early
            new Book { Title = "B clamp", Author = "A", Status = MediaStatus.Dropped, DropReason = "Too slow", CurrentPage = 500, TotalPages = 200 },    // clamps to 100% late
            new Manga { Title = "Mg mid", Status = MediaStatus.Dropped, DropReason = "Boring", CurrentChapter = 50, TotalChapters = 100 },                // 50% mid
            new Manga { Title = "Mg early", Status = MediaStatus.Dropped, DropReason = null, CurrentChapter = 0, TotalChapters = 100 },                   // 0% early, unspecified
            Show(watched: 9, total: 10) with { }, // placeholder replaced below
        };

        // Rebuild the list explicitly: shows cannot be mutated by object initializer here
        items.RemoveAt(items.Count - 1);
        var lateShow = Show(watched: 9, total: 10);
        lateShow.SetStatus(MediaStatus.Dropped);
        lateShow.DropReason = "Boring";
        var zeroShow = Show(watched: 0, total: 0);
        zeroShow.SetStatus(MediaStatus.Dropped);
        zeroShow.DropReason = "   "; // whitespace -> "unspecified"
        var movie = new Movie { Title = "Mix", Status = MediaStatus.Dropped, DropReason = "Boring" }; // default progress branch (0% early)
        items.AddRange([lateShow, zeroShow, movie]);

        var stats = Stats(totalTitles: items.Count, totalHours: 0);
        var profile = TasteProfileCalculator.Calculate(items, stats, onlyCompleted: false);

        var drops = profile.DropAnalytics;
        drops.TotalDropped.Should().Be(7);
        drops.EarlyDropCount.Should().Be(4);  // book 10%, manga 0, show 0, movie 0
        drops.MidDropCount.Should().Be(1);    // manga 50%
        drops.LateDropCount.Should().Be(2);   // clamp 100%, show 90%
        drops.AverageDropProgressPercent.Should().Be(35.7); // 250 / 7
        drops.TopReasons.Select(r => r.Reason).Should().ContainInOrder("Boring", "Too slow", "unspecified");
        drops.TopReasons[0].Count.Should().Be(3);
        drops.TopReasons[0].Percentage.Should().Be(42.9);
    }
}

/// <summary>
/// End-to-end handler tests over in-memory SQLite: aggregation SQL, advanced-stats scoping,
/// cache behavior and the reading-minutes settings validation.
/// </summary>
public class GetMediaStatsHandlerTests
{
    private static AppDbContext CreateContext()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.db");
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite($"Data Source={dbPath}")
            .Options;
        var db = new AppDbContext(options);
        db.Database.EnsureCreated();
        return db;
    }

    private static GetMediaStatsHandler CreateHandler(AppDbContext db)
        => new(db, new MemoryCache(new MemoryCacheOptions()));

    [Fact]
    public async Task HandleAsync_ShouldAggregateTotalsAcrossTypes()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new VideoGame { Title = "G1", Platform = "PC", Status = MediaStatus.Completed, HoursPlayed = 20 },
            new VideoGame { Title = "G2", Platform = "PC", Status = MediaStatus.Completed },            // no hours logged
            new Movie { Title = "M1", Status = MediaStatus.Completed, DurationMinutes = 100 },
            new Book { Title = "B1", Author = "A", Status = MediaStatus.Completed, CurrentPage = 120 },
            new Manga { Title = "Mg1", Status = MediaStatus.InProgress, CurrentChapter = 40 },
            new Movie { Title = "Planned", Status = MediaStatus.Planned },
            new TvShow
            {
                Title = "S1",
                Status = MediaStatus.InProgress,
                Seasons = [new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 5, TotalEpisodes = 10 }],
            });
        await db.SaveChangesAsync();

        var handler = CreateHandler(db);
        var result = await handler.HandleAsync(CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        var stats = result.Value!;
        stats.TotalItems.Should().Be(7);
        stats.CompletedItems.Should().Be(4);
        stats.InProgressItems.Should().Be(2);
        stats.PlannedItems.Should().Be(1);
        stats.CompletedGamesCount.Should().Be(2);
        stats.CompletedBooksCount.Should().Be(1);
        stats.CompletedMoviesCount.Should().Be(1);
        stats.TotalHoursPlayed.Should().Be(20);
        stats.TotalPagesRead.Should().Be(120);
        stats.TotalChaptersRead.Should().Be(40);
        stats.TotalEpisodesWatched.Should().Be(5);
    }

    [Fact]
    public async Task HandleAsync_EmptyDatabase_ShouldReturnZeros()
    {
        using var db = CreateContext();
        var handler = CreateHandler(db);

        var result = await handler.HandleAsync(CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        var stats = result.Value!;
        stats.TotalItems.Should().Be(0);
        stats.TotalHoursPlayed.Should().Be(0);
        stats.TotalEpisodesWatched.Should().Be(0);
    }

    [Fact]
    public async Task HandleAdvancedAsync_ShouldCalculateAndCachePerScope()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Book { Title = "Done", Author = "A", Status = MediaStatus.Completed, TotalPages = 60, Score = 8 },
            new Book { Title = "Planned", Author = "A", Status = MediaStatus.Planned, CurrentPage = 60, Score = 8 });
        await db.SaveChangesAsync();

        var handler = CreateHandler(db);

        var completed = await handler.HandleAdvancedAsync(ct: CancellationToken.None);
        completed.IsSuccess.Should().BeTrue();
        completed.Value!.TotalTitles.Should().Be(2);
        completed.Value.TotalHours.Should().Be(1.5); // 60 pages * 1.5 min

        // Second call hits the completed-scope cache: same instance
        var cached = await handler.HandleAdvancedAsync(ct: CancellationToken.None);
        cached.Value.Should().BeSameAs(completed.Value);

        // "all" scope uses a separate cache key and adds the planned book's hours
        var all = await handler.HandleAdvancedAsync("all", CancellationToken.None);
        all.IsSuccess.Should().BeTrue();
        all.Value.Should().NotBeSameAs(completed.Value);
        all.Value!.TotalHours.Should().Be(3.0);

        // A null or unknown scope behaves like "completed"
        var unknownScope = await handler.HandleAdvancedAsync("nonsense", CancellationToken.None);
        unknownScope.Value!.TotalHours.Should().Be(completed.Value.TotalHours);
    }

    [Fact]
    public async Task HandleTasteProfileAsync_ShouldCalculateAndCachePerScope()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Book { Title = "Done", Author = "A", Status = MediaStatus.Completed, TotalPages = 60, Score = 8 });
        await db.SaveChangesAsync();

        var handler = CreateHandler(db);

        var first = await handler.HandleTasteProfileAsync(ct: CancellationToken.None);
        first.IsSuccess.Should().BeTrue();
        first.Value!.Persona.Icon.Should().Be("bookworm"); // 100% book hours

        var second = await handler.HandleTasteProfileAsync(ct: CancellationToken.None);
        second.Value.Should().BeSameAs(first.Value);

        var all = await handler.HandleTasteProfileAsync("all", CancellationToken.None);
        all.IsSuccess.Should().BeTrue();
        all.Value.Should().NotBeSameAs(first.Value);
        all.Value!.SunkCost.PercentageOfTotal.Should().Be(0.0); // nothing scored 5 or below
    }

    [Fact]
    public async Task ReadingMinutes_ShouldUseValidSettingsAndFallBackWhenInvalid()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Book { Title = "B", Author = "A", Status = MediaStatus.Completed, TotalPages = 60, Score = 5 },
            new Manga { Title = "Mg", Status = MediaStatus.Dropped, CurrentChapter = 60, Score = 2 });
        await db.SaveChangesAsync();

        // In-range settings are honored ("all" scope so the dropped manga counts)
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.BookPageMinutesKey, "2.5");
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.MangaChapterMinutesKey, "9");
        var first = await CreateHandler(db).HandleAdvancedAsync("all", CancellationToken.None);
        first.Value!.TotalHours.Should().Be(11.5); // 60*2.5/60 + 60*9/60

        // Out-of-range values fall back to the defaults (1.5 / 6.0)
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.BookPageMinutesKey, "0.1");
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.MangaChapterMinutesKey, "40");
        var second = await CreateHandler(db).HandleAdvancedAsync("all", CancellationToken.None);
        second.Value!.TotalHours.Should().Be(7.5); // 60*1.5/60 + 60*6/60

        // Unparseable values fall back to the defaults as well
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.BookPageMinutesKey, "abc");
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.MangaChapterMinutesKey, "abc");
        var third = await CreateHandler(db).HandleAdvancedAsync("all", CancellationToken.None);
        third.Value!.TotalHours.Should().Be(7.5);
    }

    [Fact]
    public async Task HandleTasteProfileAsync_ShouldHonourReadingMinutesFromSettings()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Book { Title = "B", Author = "A", Status = MediaStatus.Completed, TotalPages = 60, Score = 2 });
        await db.SaveChangesAsync();
        await AppSettingStore.SetAsync(db, GetReadingSettingsHandler.BookPageMinutesKey, "2.5");

        var handler = CreateHandler(db);
        var result = await handler.HandleTasteProfileAsync(ct: CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.SunkCost.LowScoreHours.Should().Be(2.5); // 60 pages * 2.5 minutes
    }
}
