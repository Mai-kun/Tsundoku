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
    public void Apply_MissingAltTitles_ShouldLeaveStoredTitlesUntouched()
    {
        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC" };
        var stored = MediaMetadataApplier.SerializeAltTitles(["Полый рыцарь"]);
        game.AltTitles = stored;

        MediaItemUpdater.Apply(game, new UpdateMediaRequest());

        game.AltTitles.Should().Be(stored);
    }
}
