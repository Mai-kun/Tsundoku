using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

public class GetMediaListHandlerTests
{
    private static AppDbContext CreateContext()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.db");
        var db = new AppDbContext($"Data Source={dbPath}");
        db.Database.EnsureCreated();
        return db;
    }

    [Fact]
    public async Task LoadMediaItems_ShouldFilterByType()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Movie" });
        db.MediaItems.Add(new VideoGame { Title = "Game", Platform = "PC" });
        await db.SaveChangesAsync();

        var results = await db.LoadMediaItemsAsync("Movie", null, null, null, null, null, default);
        results.Should().ContainSingle(i => i is Movie);
    }

    [Fact]
    public async Task LoadMediaItems_ShouldFilterByStatus()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Done", Status = MediaStatus.Completed });
        db.MediaItems.Add(new Movie { Title = "New", Status = MediaStatus.Planned });
        await db.SaveChangesAsync();

        var results = await db.LoadMediaItemsAsync(null, MediaStatus.Completed, null, null, null, null, default);
        results.Select(i => i.Title).Should().BeEquivalentTo(["Done"]);
    }

    [Fact]
    public async Task LoadMediaItems_ShouldFilterBySearchTerm()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Dune" });
        db.MediaItems.Add(new Movie { Title = "Blade Runner" });
        db.MediaItems.Add(new Book { Title = "Unrelated", Author = "Someone", Franchise = new Franchise { Name = "Dune Universe" } });
        await db.SaveChangesAsync();

        var results = await db.LoadMediaItemsAsync(null, null, null, "Dune", null, null, default);
        results.Select(i => i.Title).Should().BeEquivalentTo(["Dune", "Unrelated"]);
    }

    [Fact]
    public async Task LoadMediaItems_ShouldSortByTitleAscendingAndDescending()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "Bravo" });
        db.MediaItems.Add(new Movie { Title = "Alpha" });
        await db.SaveChangesAsync();

        var asc = await db.LoadMediaItemsAsync(null, null, null, null, "title", "asc", default);
        var desc = await db.LoadMediaItemsAsync(null, null, null, null, "title", "desc", default);

        asc.Select(i => i.Title).Should().BeEquivalentTo(["Alpha", "Bravo"]);
        desc.Select(i => i.Title).Should().BeEquivalentTo(["Bravo", "Alpha"]);
    }

    [Fact]
    public async Task LoadMediaItems_ShouldSortByScore_WithNullsLast()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Movie { Title = "NoScore" });
        db.MediaItems.Add(new Movie { Title = "Low", Score = 3 });
        db.MediaItems.Add(new Movie { Title = "High", Score = 9 });
        await db.SaveChangesAsync();

        var asc = await db.LoadMediaItemsAsync(null, null, null, null, "score", "asc", default);
        var desc = await db.LoadMediaItemsAsync(null, null, null, null, "score", "desc", default);

        asc.Select(i => i.Title).Should().BeEquivalentTo(["Low", "High", "NoScore"], o => o.WithStrictOrdering());
        desc.Select(i => i.Title).Should().BeEquivalentTo(["High", "Low", "NoScore"], o => o.WithStrictOrdering());
    }

    [Fact]
    public async Task LoadMediaItems_ShouldDefaultToCreatedAtDescending()
    {
        using var db = CreateContext();
        var first = new Movie { Title = "First" };
        var second = new Movie { Title = "Second" };
        db.MediaItems.AddRange(first, second);
        await db.SaveChangesAsync();
        first.CreatedAt = DateTime.UtcNow.AddDays(-1);
        await db.SaveChangesAsync();

        var results = await db.LoadMediaItemsAsync(null, null, null, null, null, "desc", default);
        results.First().Title.Should().Be("Second");
    }
}
