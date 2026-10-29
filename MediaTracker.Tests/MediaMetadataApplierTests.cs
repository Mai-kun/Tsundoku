using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Xunit;

namespace MediaTracker.Tests;

public class MediaMetadataApplierTests
{
    private class TestMediaItem : MediaItem { public TestMediaItem() { Title = "Test"; } }

    [Fact]
    public void RemoveDisabledRatings_ShouldFilterCorrectly()
    {
        var item = new TestMediaItem { Title = "Test", ExternalRatingsJson = "[{\"Source\":\"MAL\",\"Score\":9.0},{\"Source\":\"TMDb\",\"Score\":8.0}]" };
        var disabled = new HashSet<string> { "mal" };

        MediaMetadataApplier.RemoveDisabledRatings(item, disabled);

        item.ExternalRatingsJson.Should().Contain("TMDb");
        item.ExternalRatingsJson.Should().NotContain("MAL");
    }

    [Theory]
    [InlineData(null, false)]
    [InlineData("", false)]
    [InlineData("{\"Source\":", false)] // unreadable payload is left untouched
    [InlineData("[{\"Source\":\"MAL\",\"Score\":9.0}]", true)] //kept rows are re-serialized → normalized payload
    public void RemoveDisabledRatings_ShouldBeStable_WhenNothingChanges(string? json, bool expectedChange)
    {
        var item = new TestMediaItem { Title = "Test", ExternalRatingsJson = json };
        MediaMetadataApplier.RemoveDisabledRatings(item, new HashSet<string> { "anilist" }).Should().Be(expectedChange);
        if (!expectedChange)
        {
            item.ExternalRatingsJson.Should().Be(json);
        }
    }

    [Fact]
    public void RemoveDisabledRatings_ShouldWipePayload_WhenAllSourcesDisabled()
    {
        var item = new TestMediaItem { Title = "Test", ExternalRatingsJson = "[{\"Source\":\"MAL\",\"Score\":9.0}]" };

        MediaMetadataApplier.RemoveDisabledRatings(item, new HashSet<string> { "MAL" }).Should().BeTrue();

        item.ExternalRatingsJson.Should().BeNull();
        item.ExternalRating.Should().BeNull();
        item.ExternalRatingVotes.Should().BeNull();
    }

    [Fact]
    public void RemoveDisabledRatings_ShouldDropRowsWithoutSource()
    {
        var item = new TestMediaItem { Title = "Test", ExternalRatingsJson = "[{\"Score\":9.0},{\"Source\":\"K\u0418n\",\"Score\":7.0}]" };

        MediaMetadataApplier.RemoveDisabledRatings(item, new HashSet<string> { "kinopoisk" }).Should().BeTrue();

        item.ExternalRatingsJson.Should().NotContain("Score\":9");
    }

    [Theory]
    [InlineData(null, false)]
    [InlineData("not-a-url", false)]
    [InlineData("https://example.com/x.png", true)]
    [InlineData("HTTP://EXAMPLE.COM", true)]
    public void IsExternalUrl_ShouldClassifyUrls(string? url, bool expected) =>
        MediaMetadataApplier.IsExternalUrl(url).Should().Be(expected);

    // ---- ApplyIfMissing: fills gaps only ----

    [Fact]
    public void ApplyIfMissing_ShouldFillBlankFields_OnMovie()
    {
        var movie = new Movie { Title = "Dune" };
        var external = new ExternalMediaDto
        {
            ExternalId = "123",
            Title = "Dune (ignored, overwrite never touches user title here)",
            Type = "movie",
            Description = "Space epic",
            RuntimeMinutes = 155,
            Studio = "Warner",
            Director = "Denis Villeneuve",
            OriginalTitle = "Dune Part One",
            Genres = [" Sci-Fi "],
            ReleaseYear = 2021,
            ReleaseStatus = "FINISHED",
            Cast = [new CastMemberDto("Timothee", "Paul", null)],
        };

        MediaMetadataApplier.ApplyIfMissing(movie, external).Should().BeTrue();

        movie.Description.Should().Be("Space epic");
        movie.DurationMinutes.Should().Be(155);
        movie.Studio.Should().Be("Warner");
        movie.Director.Should().Be("Denis Villeneuve");
        movie.RomajiTitle.Should().Be("Dune Part One");
        movie.Genres.Should().Be("Sci-Fi");
        movie.ReleaseYear.Should().Be(2021);
        movie.ReleaseStatus.Should().Be("FINISHED");
        movie.CastJson.Should().Contain("Paul");
    }

    [Fact]
    public void ApplyIfMissing_ShouldNotOverwriteUserValues()
    {
        var movie = new Movie { Title = "Dune", Description = "User wrote this", DurationMinutes = 999, Studio = "User" };
        var external = new ExternalMediaDto
        {
            ExternalId = "123",
            Title = "Different",
            Type = "movie",
            Description = "Provider text",
            RuntimeMinutes = 155,
            Studio = "Warner",
        };

        MediaMetadataApplier.ApplyIfMissing(movie, external).Should().BeFalse();

        movie.Description.Should().Be("User wrote this");
        movie.DurationMinutes.Should().Be(999);
        movie.Studio.Should().Be("User");
    }

    [Fact]
    public void ApplyIfMissing_ShouldFillBookGaps()
    {
        var book = new Book { Title = "The Hobbit", Author = null! };
        var external = new ExternalMediaDto
        {
            ExternalId = "b1",
            Title = "The Hobbit",
            Type = "book",
            Author = "Tolkien",
            TotalCount = 310,
        };

        MediaMetadataApplier.ApplyIfMissing(book, external).Should().BeTrue();

        book.Author.Should().Be("Tolkien");
        book.TotalPages.Should().Be(310);
    }

    [Fact]
    public void ApplyIfMissing_ShouldFillMangaGaps()
    {
        var manga = new Manga { Title = "One Piece" };
        var external = new ExternalMediaDto
        {
            ExternalId = "m1",
            Title = "One Piece",
            Type = "manga",
            Chapters = 1122,
            Volumes = 105,
            Author = "Oda",
            RomajiTitle = "One Piece",
            MangaFormat = "MANGA",
        };

        MediaMetadataApplier.ApplyIfMissing(manga, external).Should().BeTrue();

        manga.TotalChapters.Should().Be(1122);
        manga.TotalVolumes.Should().Be(105);
        manga.Author.Should().Be("Oda");
        manga.RomajiTitle.Should().Be("One Piece");
        manga.Format.Should().Be("MANGA");
    }

    [Fact]
    public void ApplyIfMissing_ShouldFillGameStudioAndFallbackReleaseStatus()
    {
        var game = new VideoGame { Title = "Portal", Platform = "PC" };
        var external = new ExternalMediaDto
        {
            ExternalId = "g1",
            Title = "Portal",
            Type = "game",
            Studio = "Valve",
            EndDate = "2007-10-10",
        };

        MediaMetadataApplier.ApplyIfMissing(game, external).Should().BeTrue();

        game.Studio.Should().Be("Valve");
        // No explicit release status; the past end date derives one
        game.ReleaseStatus.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void ApplyIfMissing_ShouldCreateFirstSeason_FromBareEpisodeCount()
    {
        var show = new TvShow { Title = "Severance" };
        var external = new ExternalMediaDto
        {
            ExternalId = "tv1",
            Title = "Severance",
            Type = "tvshow",
            TotalCount = 9,
            RuntimeMinutes = 45,
            Studio = "Apple TV+",
        };

        MediaMetadataApplier.ApplyIfMissing(show, external).Should().BeTrue();

        show.EpisodeDurationMinutes.Should().Be(45);
        show.Studio.Should().Be("Apple TV+");
        show.Network.Should().Be("Apple TV+");
        show.Seasons.Should().ContainSingle(s => s.TotalEpisodes == 9);
    }

    [Fact]
    public void ApplyIfMissing_ShouldCreateSeasons_FromSeasonList_OnlyWhenEmpty()
    {
        var show = new TvShow { Title = "Severance" };
        var external = new ExternalMediaDto
        {
            ExternalId = "tv1",
            Title = "Severance",
            Type = "tvshow",
            Seasons =
            [
                new ExternalSeasonDto { Number = 1, Title = "S1", TotalEpisodes = 9 },
                new ExternalSeasonDto { Number = 2, Title = "S2", TotalEpisodes = 10 },
            ],
        };

        MediaMetadataApplier.ApplyIfMissing(show, external).Should().BeTrue();
        show.Seasons.Should().HaveCount(2);

        // Фиктивно "user data": refresh must not pile up duplicates
        var before = show.Seasons.Count;
        MediaMetadataApplier.ApplyIfMissing(show, external).Should().BeFalse();
        show.Seasons.Should().HaveCount(before);
    }

    [Fact]
    public void ApplyIfMissing_ShouldReportNoChange_WhenNothingToFill()
    {
        var movie = new Movie
        {
            Title = "Complete",
            Description = "d",
            Studio = "s",
            Director = "dir",
            RomajiTitle = "r",
            DurationMinutes = 100,
            Genres = "Sci-Fi",
            ReleaseYear = 2001,
            ReleaseDate = new DateTime(2001, 1, 1),
            ReleaseStatus = "FINISHED",
            CreatorImageUrl = "local/co.jpg",
        };
        var external = new ExternalMediaDto { ExternalId = "x", Title = "Complete", Type = "movie" };

        MediaMetadataApplier.ApplyIfMissing(movie, external).Should().BeFalse();
    }

    // ---- ApplyOverwriteAsync: provider data is authoritative ----

    private sealed class StubImageStorage : MediaTracker.Server.Infrastructure.Storage.IImageStorageService
    {
        public Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default, string folder = "cover")
            => Task.FromResult<string?>($"local/{itemId}/{folder}.webp");

        public Task<MediaCoverItemDto?> SaveCoverVariantAsync(
            string externalUrl, Guid itemId, string? source = null, CancellationToken ct = default) =>
            Task.FromResult<MediaCoverItemDto?>(new MediaCoverItemDto(
                "v1",
                $"/media-assets/{itemId}/covers/v1/thumb.webp",
                $"/media-assets/{itemId}/covers/v1/original.webp",
                source,
                DateTime.UtcNow));

        public Task<MediaCoverItemDto?> SaveCoverVariantAsync(
            Stream content, Guid itemId, string? source = null, CancellationToken ct = default) =>
            Task.FromResult<MediaCoverItemDto?>(new MediaCoverItemDto(
                "v1",
                $"/media-assets/{itemId}/covers/v1/thumb.webp",
                $"/media-assets/{itemId}/covers/v1/original.webp",
                source,
                DateTime.UtcNow));

        public void DeleteCoverVariant(Guid itemId, string coverId) { }

        public void DeleteCover(string? localCoverUrl) { }

        public void DeleteMediaFolder(Guid mediaId) { }
    }

    [Fact]
    public async Task ApplyOverwrite_ShouldOverwriteAuthoritativeFields()
    {
        var movie = new Movie
        {
            Title = "Old user title",
            Description = "Will be replaced",
            Score = 8,
            Studio = "Gone",
            Director = "Gone",
            DurationMinutes = 1,
            ExternalRatingsJson = "old",
        };
        var external = new ExternalMediaDto
        {
            ExternalId = "123",
            Title = "Dune",
            Type = "movie",
            ExternalSource = "TMDb",
            Description = "Provider synopsis",
            CoverUrl = "https://cdn/dune.jpg",
            RuntimeMinutes = 155,
            Studio = "Warner",
            Director = "Denis Villeneuve",
            OriginalLanguage = "en",
            CountryOfOrigin = "US",
            Rating = 8.4,
            RatingVotes = 1234,
            ReleaseDate = "2021-10-22",
            Genres = ["Sci-Fi"],
            Cast = [new CastMemberDto("Timothee", "Paul", null)],
            Staff = [new ExternalStaffMemberDto("Denis Villeneuve", "Director", null)],
            Ratings = [new ExternalRatingDto { Source = "TMDB", Rating = 8.4, Votes = 1234 }],
        };

        await MediaMetadataApplier.ApplyOverwriteAsync(movie, external, new StubImageStorage(), CancellationToken.None);

        movie.Title.Should().Be("Dune");
        movie.Description.Should().Be("Provider synopsis");
        movie.CoverUrl.Should().Be($"/media-assets/{movie.Id}/covers/v1/thumb.webp");
        movie.CoversJson.Should().NotBeNullOrEmpty();
        movie.ExternalId.Should().Be("123");
        movie.ExternalSource.Should().Be("TMDb");
        movie.ExternalRating.Should().Be(8.4);
        movie.ExternalRatingVotes.Should().Be(1234);
        movie.OriginalLanguage.Should().Be("en");
        movie.CountryOfOrigin.Should().Be("US");
        movie.CastJson.Should().Contain("Paul");
        movie.StaffJson.Should().Contain("Denis Villeneuve");
        movie.ReleaseDate.Should().Be(new DateTime(2021, 10, 22));
        movie.Genres.Should().Be("Sci-Fi");
        movie.DurationMinutes.Should().Be(155);
        movie.Studio.Should().Be("Warner");
        movie.Director.Should().Be("Denis Villeneuve");
        movie.ExternalRatingsJson.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task ApplyOverwrite_ShouldKeepLocalCover_WhenSourceHasNone()
    {
        var movie = new Movie { Title = "Old", CoverUrl = "local/keep.webp", Score = 1 };
        var external = new ExternalMediaDto { ExternalId = "e", Title = "New", Type = "movie" };

        await MediaMetadataApplier.ApplyOverwriteAsync(movie, external, new StubImageStorage(), CancellationToken.None);

        movie.Title.Should().Be("New");
        movie.CoverUrl.Should().Be("local/keep.webp");
    }

    [Fact]
    public async Task ApplyOverwrite_ShouldKeepScoreAndProgress()
    {
        var manga = new Manga { Title = "Old", Score = 9, Status = MediaStatus.Completed };
        var external = new ExternalMediaDto { ExternalId = "e", Title = "New", Type = "manga", Rating = 6.1 };

        await MediaMetadataApplier.ApplyOverwriteAsync(manga, external, new StubImageStorage(), CancellationToken.None);

        manga.Score.Should().Be(9);
        manga.Status.Should().Be(MediaStatus.Completed);
        manga.ExternalRating.Should().Be(6.1);
    }
}
