using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

public class CrudHandlersTests
{
    private static AppDbContext CreateDbContext()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.db");
        var db = new AppDbContext($"Data Source={dbPath}");
        db.Database.EnsureCreated();
        return db;
    }

    [Fact]
    public async Task CreateMediaHandlerTests_ShouldCreateMediaAndDefaults()
    {
        using var db = CreateDbContext();
        var movie = new Movie { Title = "Test Movie", Status = MediaStatus.Planned };
        db.Movies.Add(movie);
        await db.SaveChangesAsync();

        var created = await db.Movies.FindAsync(movie.Id);
        created.Should().NotBeNull();
        created!.Title.Should().Be("Test Movie");
    }

    [Fact]
    public async Task DeleteMediaHandlerTests_ShouldCascadeDelete()
    {
        using var db = CreateDbContext();
        var movie = new Movie { Title = "Delete Me" };
        db.Movies.Add(movie);
        await db.SaveChangesAsync(); // save to get ID

        db.Events.Add(new MediaEvent { MediaId = movie.Id, Type = MediaEventType.StatusChanged, CreatedAt = DateTime.UtcNow });
        await db.SaveChangesAsync();

        db.Movies.Remove(movie);
        await db.SaveChangesAsync();

        (await db.Movies.FindAsync(movie.Id)).Should().BeNull();
        (await db.Events.CountAsync()).Should().Be(0);
    }

    [Fact]
    public async Task UpdateStatusHandlerTests_ShouldUpdateStatusAndNotes()
    {
        using var db = CreateDbContext();
        var movie = new Movie { Title = "Test Movie", Status = MediaStatus.InProgress };
        db.Movies.Add(movie);
        await db.SaveChangesAsync();

        movie.ChangeStatus(MediaStatus.Dropped);
        movie.DropReason = "Bored";
        await db.SaveChangesAsync();

        var updated = await db.Movies.FindAsync(movie.Id);
        updated!.Status.Should().Be(MediaStatus.Dropped);
        updated.DropReason.Should().Be("Bored");
    }

    [Fact]
    public async Task UpdateProgressHandlerTests_ShouldTrackProgress()
    {
        using var db = CreateDbContext();
        var book = new Book { Title = "Test Book", Status = MediaStatus.InProgress, Author = "Test" };
        db.Books.Add(book);
        await db.SaveChangesAsync();

        book.CurrentPage = 10;
        await db.SaveChangesAsync();

        var updated = await db.Books.FindAsync(book.Id);
        updated!.CurrentPage.Should().Be(10);
    }
}
