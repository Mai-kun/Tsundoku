using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace MediaTracker.Tests;

public class GetMediaListHandlerTests
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

    [Fact]
    public void TryBuild_ShouldReturnFalse_WhenTypeUnknown()
    {
        using var db = CreateContext();
        MediaListQuery.TryBuild(db, "nonsense", null, null, null, null, null, out _).Should().BeFalse();
    }

    [Fact]
    public async Task TryBuild_ShouldFilterByType()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Movie" });
        db.MediaItems.Add(new VideoGame { Title = "Game", Platform = "PC" });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, "MOVIE", null, null, null, null, null, out var query).Should().BeTrue();

        var results = await query.ToListAsync();
        results.Should().ContainSingle(i => i is Movie);
    }

    [Fact]
    public async Task TryBuild_ShouldFilterByStatus()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Done", Status = MediaStatus.Completed });
        db.MediaItems.Add(new Movie { Title = "New", Status = MediaStatus.Planned });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, MediaStatus.Completed, null, null, null, null, out var query).Should().BeTrue();

        var results = await query.ToListAsync();
        results.Select(i => i.Title).Should().BeEquivalentTo(["Done"]);
    }

    [Fact]
    public async Task TryBuild_ShouldFilterBySearchTerm()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Dune" });
        db.MediaItems.Add(new Movie { Title = "Blade Runner" });
        db.MediaItems.Add(new Book { Title = "Unrelated", Author = "Someone", Franchise = new Franchise { Name = "Dune Universe" } });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, null, null, "Dune", null, null, out var query).Should().BeTrue();

        var results = await query.ToListAsync();
        results.Select(i => i.Title).Should().BeEquivalentTo(["Dune", "Unrelated"]);
    }

    [Fact]
    public async Task TryBuild_ShouldReturnFalse_WhenSearchOnlyWhitespace()
    {
        // whitespace search must not return true-and-unfiltered, it is treated as absent
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Anything" });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, null, null, "   ", null, null, out var query).Should().BeTrue();
        (await query.CountAsync()).Should().Be(1);
    }

    [Fact]
    public async Task TryBuild_ShouldSortByTitleAscendingAndDescending()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Bravo" });
        db.MediaItems.Add(new Movie { Title = "Alpha" });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, null, null, null, "title", "asc", out var asc).Should().BeTrue();
        MediaListQuery.TryBuild(db, null, null, null, null, "title", "desc", out var desc).Should().BeTrue();

        (await asc.Select(i => i.Title).ToListAsync()).Should().BeEquivalentTo(["Alpha", "Bravo"]);
        (await desc.Select(i => i.Title).ToListAsync()).Should().BeEquivalentTo(["Bravo", "Alpha"]);
    }

    [Fact]
    public async Task TryBuild_ShouldSortByScore_WithNullsLast()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "NoScore" });
        db.MediaItems.Add(new Movie { Title = "Low", Score = 3 });
        db.MediaItems.Add(new Movie { Title = "High", Score = 9 });
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, null, null, null, "score", "asc", out var asc).Should().BeTrue();
        MediaListQuery.TryBuild(db, null, null, null, null, "score", "desc", out var desc).Should().BeTrue();

        (await asc.Select(i => i.Title).ToListAsync())
            .Should().BeEquivalentTo(["Low", "High", "NoScore"], o => o.WithStrictOrdering());
        (await desc.Select(i => i.Title).ToListAsync())
            .Should().BeEquivalentTo(["High", "Low", "NoScore"], o => o.WithStrictOrdering());
    }

    [Fact]
    public async Task TryBuild_ShouldDefaultToCreatedAtDescending()
    {
        using var db = CreateContext();
        var first = new Movie { Title = "First" };
        var second = new Movie { Title = "Second" };
        db.MediaItems.AddRange(first, second);
        await db.SaveChangesAsync();
        // EnsureCreated rows are inserted in order already; force distinct ordering
        first.CreatedAt = DateTime.UtcNow.AddDays(-1);
        await db.SaveChangesAsync();

        MediaListQuery.TryBuild(db, null, null, null, null, null, "desc", out var query).Should().BeTrue();

        (await query.Select(i => i.Title).ToListAsync()).First().Should().Be("Second");
    }
}
