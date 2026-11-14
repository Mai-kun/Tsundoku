using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.Imdb;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Cinemeta episode mapping: the series meta (verified against
/// v3-cinemeta.strem.io/meta/series/tt0944947.json) carries a "videos" array with season,
/// episode/number, name, released, overview and thumbnail per entry.
/// </summary>
public class ImdbCinemetaTests
{
    private static CinemetaVideo Video(int season, int episode, string? name = "Inside Game of Thrones",
        string? released = "2010-12-06T05:00:00.000Z", int? number = null, string? title = null) =>
        new()
        {
            Season = season,
            Episode = episode,
            Number = number,
            Name = name,
            Title = title,
            Released = released,
        };

    [Fact]
    public void MapSeasons_GroupsBySeasonAndSortsEpisodes()
    {
        var seasons = ImdbMetadataProvider.MapSeasons(
        [
            Video(1, 2, "The Kingsroad"),
            Video(1, 1, "Winter Is Coming"),
            Video(2, 1, "The North Remembers"),
        ]);

        seasons.Should().HaveCount(2);
        seasons[0].Number.Should().Be(1);
        seasons[0].TotalEpisodes.Should().Be(2);
        seasons[0].Episodes![0].Number.Should().Be(1);
        seasons[0].Episodes![0].Title.Should().Be("Winter Is Coming");
        seasons[0].Episodes![1].Number.Should().Be(2);
        seasons[1].Number.Should().Be(2);
        seasons[1].Episodes.Should().ContainSingle().Which.Number.Should().Be(1);
    }

    [Fact]
    public void MapSeasons_SkipsSeasonZeroSpecials()
    {
        var seasons = ImdbMetadataProvider.MapSeasons(
        [
            Video(0, 1, "Inside Game of Thrones"),
            Video(0, 2, "15-Minute Preview"),
            Video(1, 1, "Winter Is Coming"),
        ]);

        seasons.Should().ContainSingle();
        seasons[0].Number.Should().Be(1);
    }

    [Fact]
    public void MapSeasons_FallsBackToNumberFieldAndTrimmedAirDate()
    {
        var seasons = ImdbMetadataProvider.MapSeasons(
        [
            // Older metas carry no "episode", only "number"; the ISO air date trims to yyyy-MM-dd.
            new CinemetaVideo { Season = 3, Number = 7, Name = null, Released = "2013-05-20T00:00:00.000Z" },
        ]);

        seasons.Should().ContainSingle();
        var episode = seasons[0].Episodes![0];
        episode.Number.Should().Be(7);
        episode.Title.Should().Be("Episode 7");
        episode.AirDate.Should().Be("2013-05-20");
    }

    [Fact]
    public void MapSeasons_DropsEntriesWithoutUsableNumber()
    {
        var seasons = ImdbMetadataProvider.MapSeasons(
        [
            new CinemetaVideo { Season = 1, Episode = 0, Number = null, Name = "Unnumbered extra" },
            Video(1, 1, "Winter Is Coming"),
        ]);

        seasons.Should().ContainSingle();
        seasons[0].Episodes.Should().ContainSingle().Which.Number.Should().Be(1);
    }

    [Fact]
    public void MapSeasons_AnswersEmptyForNoVideos()
    {
        ImdbMetadataProvider.MapSeasons(null).Should().BeEmpty();
        ImdbMetadataProvider.MapSeasons([]).Should().BeEmpty();
    }
}
