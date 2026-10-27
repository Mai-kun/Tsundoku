using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>Smart lists and franchise inference: pure logic + small db round-trips.</summary>
public class SmartListAndFranchiseTests
{
    private static AppDbContext CreateContext()
    {
        var options = new Microsoft.EntityFrameworkCore.DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite($"Data Source={Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.db")}")
            .Options;
        var db = new AppDbContext(options);
        db.Database.EnsureCreated();
        return db;
    }

    // ---- SmartListEvaluator ----

    private static List<MediaItem> Items() =>
    [
        new VideoGame { Title = "Beta Game", Platform = "PC", Score = 9, ExternalRating = 8.5, ReleaseYear = 2020, Genres = "RPG, Action", CreatedAt = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc), Studio = "Valve", HoursPlayed = 10 },
        new Movie { Title = "Alpha Film", Score = 5, ExternalRating = 7.0, ReleaseYear = 2000, Genres = "Drama", Studio = "A24", Director = "Nobody", DurationMinutes = 95, CreatedAt = new DateTime(2021, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
        new Book { Title = "Middle Book", Score = 7, Author = "Sanderson", TotalPages = 500, ReleaseYear = 2011, CreatedAt = new DateTime(2019, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
        new Manga { Title = "Zed Manga", Author = "Oda", TotalChapters = 100, ReleaseYear = 2022, CreatedAt = new DateTime(2018, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
        new TvShow { Title = "Gamma Tv", Studio = "HBO", Score = null, Genres = "RPG", ReleaseYear = 2023, CreatedAt = new DateTime(2017, 1, 1, 0, 0, 0, DateTimeKind.Utc) },
    ];

    [Fact]
    public void Evaluate_ShouldFilterByUnratedGenreYearAndLimits()
    {
        var items = Items();

        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { OnlyUnrated = true }).Count.Should().Be(2);

        var genre = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Genres = ["RPG"] });
        genre.Select(i => i.Title).Should().BeEquivalentTo(["Beta Game", "Gamma Tv"]);

        var year = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { ReleaseYearFrom = 2020, ReleaseYearTo = 2022 });
        year.Select(i => i.Title).Should().BeEquivalentTo(["Beta Game", "Zed Manga"]);

        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MinScore = 8 }).Select(i => i.Title).Should().BeEquivalentTo(["Beta Game"]);
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MaxScore = 6 }).Select(i => i.Title).Should().BeEquivalentTo(["Alpha Film"]);
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MinExternalRating = 8.0 }).Select(i => i.Title).Should().BeEquivalentTo(["Beta Game"]);
    }

    [Fact]
    public void Evaluate_ShouldFilterByVolumeLimits()
    {
        var items = Items();

        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MaxDurationMinutes = 100 })
            .Select(i => i is Movie or TvShow ? i.Title : null).Where(t => t != null)
            .Should().BeEquivalentTo(["Alpha Film", "Gamma Tv"]);
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MaxEpisodes = 0 }).Count.Should().Be(4);
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MaxPages = 400 }).Select(i => i.Title).Should().NotContain("Middle Book");
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MaxChapters = 50 }).Select(i => i.Title).Should().NotContain("Zed Manga");
    }

    [Fact]
    public void Evaluate_ShouldFilterByCreator()
    {
        var items = Items();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { CreatorContains = "oda" })
            .Select(i => i.Title).Should().BeEquivalentTo(["Zed Manga"]);
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { CreatorContains = "valve" })
            .Select(i => i.Title).Should().BeEquivalentTo(["Beta Game"]);
    }

    [Fact]
    public void Evaluate_ShouldSortEveryFieldBothDirections()
    {
        var items = Items();

        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "score", SortOrder = "asc" })
            .Select(i => i.Score ?? 0).Should().BeInAscendingOrder();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "score", SortOrder = "desc" })
            .Select(i => i.Score ?? 0).Should().BeInDescendingOrder();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "externalRating", SortOrder = "asc" })
            .Select(i => i.ExternalRating ?? 0).Should().BeInAscendingOrder();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "releaseYear", SortOrder = "asc" })
            .Select(i => i.ReleaseYear ?? 0).Should().BeInAscendingOrder();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "title", SortOrder = "asc" })
            .Select(i => i.Title).Should().BeInAscendingOrder();
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "title", SortOrder = "desc" })
            .Select(i => i.Title).Should().BeInDescendingOrder();
        var createdAsc = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "createdAt", SortOrder = "asc" });
        createdAsc.First().Title.Should().Be("Gamma Tv");

        // Default sort (no field) → created desc
        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { }).First().Title.Should()
            .Be(items.MaxBy(i => i.CreatedAt)!.Title);

        SmartListEvaluator.Evaluate(items, new SmartListQueryDto { SortBy = "score", Limit = 2 }).Should().HaveCount(2);
    }

    [Fact]
    public void ParseQuery_ShouldRejectBrokenJson()
    {
        SmartListEvaluator.ParseQuery(null).Should().BeNull();
        SmartListEvaluator.ParseQuery("").Should().BeNull();
        SmartListEvaluator.ParseQuery("[broken").Should().BeNull();
        SmartListEvaluator.ParseQuery("{\"genres\":[\"RPG\"]}").Should().NotBeNull();
    }

    // ---- FranchiseService ----

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public void InferFranchiseName_ShouldReturnNull_ForBlankInput(string? title) =>
        new FranchiseService().InferFranchiseName(title).Should().BeNull();

    [Theory]
    [InlineData("Attack on Titan", null)]
    [InlineData("Naruto: Shippuden", "Naruto")]
    [InlineData("Dune - Part Two", "Dune")]
    [InlineData("Bad / slash", "Bad")]
    public void InferFranchiseName_ShouldExtractPrefix(string title, string? expected) =>
        new FranchiseService().InferFranchiseName(title).Should().Be(expected);

    [Fact]
    public async Task AutoBackfill_ShouldGroupSiblingsAndSkipLonelyTitles()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Movie { Title = "Mass Effect: Revelation" },
            new Movie { Title = "Mass Effect: Ascension" },
            new Movie { Title = "One and only" });
        await db.SaveChangesAsync();

        await new FranchiseService().AutoBackfillFranchisesAsync(db);

        var franchise = db.Franchises.FirstOrDefault(f => f.Name.StartsWith("Mass Effect"));
        franchise.Should().NotBeNull();
        db.MediaItems.ToList().Count(m => m.FranchiseId == franchise!.Id).Should().Be(2);
        db.MediaItems.Single(m => m.Title == "One and only").FranchiseId.Should().BeNull();
    }

    [Fact]
    public async Task LinkFranchiseOnCreate_ShouldReuseExistingFranchise()
    {
        using var db = CreateContext();
        var existing = new Franchise { Name = "Naruto" };
        db.Franchises.Add(existing);
        var item = new Manga { Title = "Naruto: Side Story", Author = "Kishimoto" };
        db.MediaItems.Add(item);
        await db.SaveChangesAsync();

        await new FranchiseService().LinkFranchiseOnCreateAsync(db, item, null);

        item.FranchiseId.Should().Be(existing.Id);

        // Empty input is a no-op
        var orphan = new Movie { Title = "Random" };
        db.MediaItems.Add(orphan);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        var reloaded = db.MediaItems.Single(m => m.Id == orphan.Id);
        await new FranchiseService().LinkFranchiseOnCreateAsync(db, reloaded, "   ");
        reloaded.FranchiseId.Should().BeNull();
    }

    [Fact]
    public async Task LinkFranchiseOnCreate_ShouldCreateFranchise_WhenRequestedName()
    {
        using var db = CreateContext();
        var item = new Movie { Title = "Inception" };
        db.MediaItems.Add(item);
        await db.SaveChangesAsync();

        await new FranchiseService().LinkFranchiseOnCreateAsync(db, item, "Nolan Universe");

        item.FranchiseId.Should().NotBeNull();
        await db.SaveChangesAsync();
        db.Franchises.Should().Contain(f => f.Name == "Nolan Universe");
    }
}
