using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Domain.Rules;
using Xunit;

namespace MediaTracker.Tests;

public class MediaItemUpdaterTests
{
    private class TestMediaItem : MediaItem { public TestMediaItem() : base() { Title = "Test"; } }

    [Fact]
    public void Apply_UpdateMediaRequest_ShouldApplyFields()
    {
        var item = new TestMediaItem { Title = "Original" };
        var request = new UpdateMediaRequest
        {
            Title = "Updated",
            Score = 5,
            ClearScore = true
        };

        MediaItemUpdater.Apply(item, request);

        item.Title.Should().Be("Updated");
        item.Score.Should().BeNull();
        item.IsCustomEdited.Should().BeTrue();
    }

    [Fact]
    public void Apply_AltTitles_ShouldApplyToEveryCategory()
    {
        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC" };
        var request = new UpdateMediaRequest { AltTitles = ["HK Silksong Prototype", "Полый рыцарь"] };

        MediaItemUpdater.Apply(game, request);

        MediaMetadataApplier.DeserializeAltTitles(game.AltTitles)
            .Should().BeEquivalentTo(["HK Silksong Prototype", "Полый рыцарь"]);
    }

    [Fact]
    public void Apply_EmptyAltTitlesList_ShouldClearStoredTitles()
    {
        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC" };
        game.AltTitles = MediaMetadataApplier.SerializeAltTitles(["Полый рыцарь"]);

        MediaItemUpdater.Apply(game, new UpdateMediaRequest { AltTitles = [] });

        game.AltTitles.Should().BeNull();
    }

    [Fact]
    public void Apply_StatusChangeFromCompleted_ShouldResetProgress()
    {
        // Rule 2 through the edit-form endpoint: leaving Completed resets the counters.
        var book = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300, CurrentChapter = 21 };
        book.ChangeStatus(MediaStatus.Completed);

        MediaItemUpdater.Apply(book, new UpdateMediaRequest { Status = MediaStatus.Planned });

        book.Status.Should().Be(MediaStatus.Planned);
        book.CurrentPage.Should().Be(0);
        book.CurrentChapter.Should().Be(0);

        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC", HoursPlayed = 42 };
        game.ChangeStatus(MediaStatus.Completed);

        MediaItemUpdater.Apply(game, new UpdateMediaRequest { Status = MediaStatus.InProgress });

        game.Status.Should().Be(MediaStatus.InProgress);
        game.HoursPlayed.Should().Be(0);
    }

    [Fact]
    public void Apply_StatusChangeNotFromCompleted_ShouldKeepProgress()
    {
        // InProgress -> Planned through the edit-form endpoint keeps the counters.
        var book = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300, Status = MediaStatus.InProgress };

        MediaItemUpdater.Apply(book, new UpdateMediaRequest { Status = MediaStatus.Planned });

        book.Status.Should().Be(MediaStatus.Planned);
        book.CurrentPage.Should().Be(300);
    }

    [Fact]
    public void Apply_StatusChangeFromCompleted_ExplicitProgressWins()
    {
        // Progress fields carried by the same request are re-applied after the rule-2 reset.
        var book = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300 };
        book.ChangeStatus(MediaStatus.Completed);

        MediaItemUpdater.Apply(book, new UpdateMediaRequest { Status = MediaStatus.OnHold, CurrentPage = 42 });

        book.Status.Should().Be(MediaStatus.OnHold);
        book.CurrentPage.Should().Be(42);
    }

    [Fact]
    public void Apply_MissingAltTitles_ShouldLeaveStoredTitlesUntouched()
    {
        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC" };
        var stored = MediaMetadataApplier.SerializeAltTitles(["Полый рыцарь"]);
        game.AltTitles = stored;

        MediaItemUpdater.Apply(game, new UpdateMediaRequest());

        game.AltTitles.Should().Be(stored);
    }
}
