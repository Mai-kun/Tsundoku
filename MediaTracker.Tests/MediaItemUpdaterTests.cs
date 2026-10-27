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
}
