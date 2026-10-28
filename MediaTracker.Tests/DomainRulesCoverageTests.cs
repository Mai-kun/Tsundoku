using System.Text.Json;
using FluentAssertions;
using MediaTracker.Server.Common.Middleware;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Closes the remaining branch gaps in the domain rules: applier overwrite/enrich branches per
/// entity type, updater partial updates and clear flags, factory type mapping, TvShow season
/// roll-ups and the global exception handler.
/// </summary>
public class DomainRulesCoverageTests
{
    // ---- MediaMetadataApplier ----

    [Fact]
    public void RemoveDisabledRatings_EmptyDisabledSet_ShouldNotParse()
    {
        var item = new Movie { Title = "T", ExternalRatingsJson = "[{\"Source\":\"MAL\",\"Score\":9.0}]" };

        MediaMetadataApplier.RemoveDisabledRatings(item, new HashSet<string>()).Should().BeFalse();

        item.ExternalRatingsJson.Should().Contain("MAL");
    }

    private sealed class StubImageStorage : IImageStorageService
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
    public async Task ApplyOverwrite_TvShow_ShouldUpdateExistingSeasonAndCreateMissingOne()
    {
        var show = new TvShow { Title = "Old" };
        var existing = new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 8, EpisodesData = "old", TvShowId = show.Id };
        show.Seasons.Add(existing);
        TvSeason? tracked = null;
        var external = new ExternalMediaDto
        {
            ExternalId = "tv1",
            Title = "Updated",
            Type = "tvshow",
            RuntimeMinutes = 42,
            Studio = "HBO",
            OriginalTitle = "Orig Romaji",
            Seasons =
            [
                new ExternalSeasonDto { Number = 1, TotalEpisodes = 12 }, // existing row is backfilled
                new ExternalSeasonDto
                {
                    Number = 3,
                    TotalEpisodes = 4,
                    Episodes = [new ExternalEpisodeDto { Number = 1, Title = "E1" }],
                },
            ],
        };

        await MediaMetadataApplier.ApplyOverwriteAsync(
            show, external, new StubImageStorage(), CancellationToken.None,
            trackNewSeason: s => tracked = s);

        show.Title.Should().Be("Updated");
        show.EpisodeDurationMinutes.Should().Be(42);
        show.Studio.Should().Be("HBO");
        show.Network.Should().Be("HBO");
        show.RomajiTitle.Should().Be("Orig Romaji");
        existing.TotalEpisodes.Should().Be(12);
        existing.EpisodesData.Should().Be("old"); // no episodes for S1 → stored payload kept

        var created = tracked ?? show.Seasons.Single(s => s.SeasonNumber == 3);
        created.SeasonNumber.Should().Be(3);
        created.Title.Should().Be("Season 3");
        created.TotalEpisodes.Should().Be(4);
        created.EpisodesData.Should().Contain("E1");
        created.TvShowId.Should().Be(show.Id);
        show.Seasons.Should().HaveCount(2);
    }

    [Fact]
    public async Task ApplyOverwrite_TvShow_EpisodesOnly_ShouldCreateFirstSeasonOrBackfill()
    {
        var empty = new TvShow { Title = "Fringe" };
        var external = new ExternalMediaDto
        {
            ExternalId = "e1",
            Title = "Fringe",
            Type = "tvshow",
            Episodes =
            [
                new ExternalEpisodeDto { Number = 1, Title = "Pilot" },
                new ExternalEpisodeDto { Number = 2, Title = "The Same Old Story" },
            ],
        };
        TvSeason? tracked = null;

        await MediaMetadataApplier.ApplyOverwriteAsync(
            empty, external, new StubImageStorage(), CancellationToken.None,
            trackNewSeason: s => tracked = s);

        empty.Seasons.Should().ContainSingle();
        var first = empty.Seasons[0];
        first.SeasonNumber.Should().Be(1);
        first.Title.Should().Be("Season 1");
        first.TotalEpisodes.Should().Be(2); // TotalCount absent → episode list length
        first.EpisodesData.Should().Contain("Pilot");
        (tracked ?? first).Should().BeSameAs(first);

        // A show that already has a first season gets its counters backfilled instead
        var withSeason = new TvShow { Title = "Fringe 2" };
        withSeason.Seasons.Add(new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 8 });
        await MediaMetadataApplier.ApplyOverwriteAsync(withSeason, external, new StubImageStorage(), CancellationToken.None);
        withSeason.Seasons.Should().HaveCount(1);
        withSeason.Seasons[0].TotalEpisodes.Should().Be(2);
        withSeason.Seasons[0].EpisodesData.Should().Contain("Pilot");
    }

    [Fact]
    public async Task ApplyOverwrite_GameAndBook_ShouldWriteTypeSpecificFields()
    {
        var game = new VideoGame { Title = "Old", Platform = "Steam", ExternalSource = " estaban" };
        var gameExternal = new ExternalMediaDto
        {
            ExternalId = "g1",
            Title = "Elden Ring",
            Type = "game",
            Platform = "PC",
            Studio = "FromSoftware",
            Rating = 9.3,
            RatingVotes = 100,
            EndDate = "not-a-date", // invalid string → ParseDate keeps EndDate null
        };

        await MediaMetadataApplier.ApplyOverwriteAsync(game, gameExternal, new StubImageStorage(), CancellationToken.None);

        game.Platform.Should().Be("PC");
        game.Studio.Should().Be("FromSoftware");
        game.ExternalSource.Should().Be(" estaban"); // null source does not erase the stored one
        game.EndDate.Should().BeNull();

        var book = new Book { Title = "Old", Author = "Gone" };
        var bookExternal = new ExternalMediaDto
        {
            ExternalId = "b1",
            Title = "Dune",
            Type = "book",
            TotalCount = 412,
            Author = "Herbert",
        };

        await MediaMetadataApplier.ApplyOverwriteAsync(book, bookExternal, new StubImageStorage(), CancellationToken.None);

        book.TotalPages.Should().Be(412);
        book.Author.Should().Be("Herbert");
    }

    [Fact]
    public async Task ApplyOverwrite_Movie_ShouldUseCountAndAuthorFallbacks()
    {
        var movie = new Movie { Title = "Old" };
        var external = new ExternalMediaDto
        {
            ExternalId = "m1",
            Title = "Dune",
            Type = "movie",
            TotalCount = 90, // RuntimeMinutes absent → TotalCount feeds the duration
            Author = "Frank Herbert", // Director absent → Author feeds it
            OriginalTitle = "Ro Title", // RomajiTitle absent → OriginalTitle feeds it
            CreatorImageUrl = "https://cdn/studio.png",
        };

        await MediaMetadataApplier.ApplyOverwriteAsync(movie, external, new StubImageStorage(), CancellationToken.None);

        movie.DurationMinutes.Should().Be(90);
        movie.Director.Should().Be("Frank Herbert");
        movie.RomajiTitle.Should().Be("Ro Title");
        movie.CreatorImageUrl.Should().Be($"local/{movie.Id}/creator.webp");
        movie.ExternalRatingsJson.Should().BeNull();
    }

    [Fact]
    public void ApplyIfMissing_ShouldFillStaffTrailerCreator_AndKeepUserContent()
    {
        var movie = new Movie { Title = "Dune", CastJson = "user cast" };
        var external = new ExternalMediaDto
        {
            ExternalId = "m1",
            Title = "Dune",
            Type = "movie",
            Description = "Provider text",
            TrailerVideoId = "abc123",
            CreatorImageUrl = "https://cdn/logo.png",
            OriginalLanguage = "en",
            CountryOfOrigin = "US",
            OriginalTitle = "Original",
            Genres = ["Sci-Fi"],
            ReleaseYear = 2021,
            ReleaseStatus = "HIATUS",
            Staff = [new ExternalStaffMemberDto("Denis Villeneuve", "Director", null)],
        };

        MediaMetadataApplier.ApplyIfMissing(movie, external).Should().BeTrue();

        movie.CastJson.Should().Be("user cast"); // enrich never replaces what the user has
        movie.StaffJson.Should().Contain("Villeneuve");
        movie.TrailerVideoId.Should().Be("abc123");
        movie.CreatorImageUrl.Should().BeNull(); // enrich stores no external creator image link
        movie.Description.Should().Be("Provider text");
        movie.OriginalLanguage.Should().Be("en");
        movie.CountryOfOrigin.Should().Be("US");
        movie.OriginalTitle.Should().Be("Original");
        movie.Genres.Should().Be("Sci-Fi");
        movie.ReleaseYear.Should().Be(2021);
        movie.ReleaseStatus.Should().Be("HIATUS");
    }

    [Fact]
    public void ApplyIfMissing_WhenEverythingFilled_ShouldReportNoChange()
    {
        var show = new TvShow
        {
            Title = "Full",
            Description = "d",
            TrailerVideoId = "t",
            CreatorImageUrl = "c",
            Genres = "Drama",
            ReleaseYear = 2020,
            ReleaseDate = new DateTime(2020, 1, 1),
            ReleaseStatus = "RELEASING",
            CastJson = "cast",
            StaffJson = "staff",
            OriginalTitle = "orig",
            OriginalLanguage = "en",
            CountryOfOrigin = "US",
            Seasons = [new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 5 }],
        };
        var external = new ExternalMediaDto
        {
            ExternalId = "s1",
            Title = "Full",
            Type = "tvshow",
            Description = "new text",
            Seasons = [new ExternalSeasonDto { Number = 2, TotalEpisodes = 0 }], // zero episodes → skipped
            ReleaseDate = "2019-01-01",
        };

        MediaMetadataApplier.ApplyIfMissing(show, external).Should().BeFalse();
        show.Seasons.Should().HaveCount(1);
        show.ReleaseDate.Should().Be(new DateTime(2020, 1, 1));
    }

    [Fact]
    public void ApplyIfMissing_NoEpisodeDataAtAll_ShouldNotCreateSeason()
    {
        var show = new TvShow { Title = "Empty" };

        MediaMetadataApplier.ApplyIfMissing(show, new ExternalMediaDto
        {
            ExternalId = "e",
            Title = "Empty",
            Type = "tvshow",
        }).Should().BeFalse();

        show.Seasons.Should().BeEmpty();
    }

    [Fact]
    public void ApplyIfMissing_MangaAndGame_FilledCounters_ShouldNotTouchThem()
    {
        var manga = new Manga { Title = "M", TotalChapters = 100, TotalVolumes = 10, Author = "A", RomajiTitle = "R", Format = "MANGA" };
        MediaMetadataApplier.ApplyIfMissing(manga, new ExternalMediaDto
        {
            ExternalId = "m",
            Title = "M",
            Type = "manga",
            TotalCount = 999,
        }).Should().BeFalse();
        manga.TotalChapters.Should().Be(100);

        var game = new VideoGame { Title = "G", Platform = "PC", Studio = "Valve" };
        MediaMetadataApplier.ApplyIfMissing(game, new ExternalMediaDto
        {
            ExternalId = "g",
            Title = "G",
            Type = "game",
            Studio = "Other",
        }).Should().BeFalse();
        game.Studio.Should().Be("Valve");
    }

    [Fact]
    public void ApplyIfMissing_ShouldPreserveSetDates_AndDeriveStatusFromDates()
    {
        var past = new Movie { Title = "Past", ReleaseDate = new DateTime(2001, 1, 1) };
        MediaMetadataApplier.ApplyIfMissing(past, new ExternalMediaDto
        {
            ExternalId = "p",
            Title = "Past",
            Type = "movie",
            ReleaseDate = "2002-01-01", // ReleaseDate already stored → kept
            EndDate = "2020-06-01",
            ReleaseStatus = "  ", // blank external status → derived from dates
        }).Should().BeTrue();
        past.ReleaseDate.Should().Be(new DateTime(2001, 1, 1));
        past.EndDate.Should().Be(new DateTime(2020, 6, 1));
        past.ReleaseStatus.Should().Be("FINISHED");

        var future = new Movie { Title = "Future" };
        MediaMetadataApplier.ApplyIfMissing(future, new ExternalMediaDto
        {
            ExternalId = "f",
            Title = "Future",
            Type = "movie",
            ReleaseDate = "2999-01-01",
        }).Should().BeTrue();
        future.ReleaseDate.Should().Be(new DateTime(2999, 1, 1));
        future.ReleaseStatus.Should().Be("NOT_YET_RELEASED");
    }

    // ---- MediaItemUpdater ----

    [Fact]
    public void Updater_FullFieldUpdate_ShouldCopyEveryField()
    {
        var manga = new Manga { Title = "Old" };
        var stamp = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var request = new UpdateMediaRequest
        {
            Title = "New",
            Score = 8,
            DetailedScoreJson = "{\"a\":1}",
            Notes = "n",
            QuotesJson = "q",
            CoverUrl = "c.jpg",
            StartedAt = stamp,
            FinishedAt = stamp,
            LastActivityAt = stamp,
            TranslatedSynopsis = "ts",
            TranslationLanguage = "ru",
            Genres = " Sci-Fi , RPG ",
            Tags = "t1,t2",
            UnlockedAchievements = "ach",
            WatchedOn = "Kinopoisk",
            UserPlatform = "Readmanga",
            FranchiseOrder = 3,
            RelatedMediaJson = "rel",
            RelatedSource = "anilist",
            AchievementsJson = "ach2",
            RecommendationsJson = "rec",
            Author = "Oda",
            RomajiTitle = "Rom",
            TotalVolumes = 105,
            CurrentVolume = 4,
            TotalChapters = 1122,
            CurrentChapter = 50,
        };

        MediaItemUpdater.Apply(manga, request);

        manga.Title.Should().Be("New");
        manga.Score.Should().Be(8);
        manga.DetailedScoreJson.Should().Be("{\"a\":1}");
        manga.Notes.Should().Be("n");
        manga.QuotesJson.Should().Be("q");
        manga.CoverUrl.Should().Be("c.jpg");
        manga.StartedAt.Should().Be(stamp);
        manga.FinishedAt.Should().Be(stamp);
        manga.LastActivityAt.Should().Be(stamp);
        manga.TranslatedSynopsis.Should().Be("ts");
        manga.TranslationLanguage.Should().Be("ru");
        manga.Genres.Should().Be("Sci-Fi, RPG");
        manga.Tags.Should().Be("t1,t2");
        manga.UnlockedAchievements.Should().Be("ach");
        manga.WatchedOn.Should().Be("Kinopoisk");
        manga.UserPlatform.Should().Be("Readmanga");
        manga.FranchiseOrder.Should().Be(3);
        manga.RelatedMediaJson.Should().Be("rel");
        manga.RelatedSource.Should().Be("anilist");
        manga.AchievementsJson.Should().Be("ach2");
        manga.RecommendationsJson.Should().Be("rec");
        manga.Author.Should().Be("Oda");
        manga.RomajiTitle.Should().Be("Rom");
        manga.TotalVolumes.Should().Be(105);
        manga.CurrentVolume.Should().Be(4);
        manga.TotalChapters.Should().Be(1122);
        manga.CurrentChapter.Should().Be(50);
        manga.IsCustomEdited.Should().BeTrue(); // a real manual edit arms the overwrite prompt
    }

    [Fact]
    public void Updater_ClearFlags_AndBlankDropFields_ShouldNullValues()
    {
        var item = new Movie
        {
            Title = "T",
            Score = 5,
            DetailedScoreJson = "d",
            WatchedOn = "vod",
            UserPlatform = "PC",
            DropReason = "x",
            DropNotes = "y",
        };
        var request = new UpdateMediaRequest
        {
            ClearScore = true,
            ClearDetailedScore = true,
            ClearWatchedOn = true,
            ClearUserPlatform = true,
            // blank drop fields are explicit empties in the request body
            DropReason = "",
            DropNotes = "",
        };

        MediaItemUpdater.Apply(item, request);

        item.Score.Should().BeNull();
        item.DetailedScoreJson.Should().BeNull();
        item.WatchedOn.Should().BeNull();
        item.UserPlatform.Should().BeNull();
        // blank drop fields are explicit empties → stored as null
        item.DropReason.Should().BeNull();
        item.DropNotes.Should().BeNull();
        item.IsCustomEdited.Should().BeTrue(); // clearing a set score is a manual edit
    }

    [Fact]
    public void Updater_StatusChange_ClearsDrops_UnlessDropped()
    {
        var cleared = new Movie { Title = "A", DropReason = "r", DropNotes = "n" };
        MediaItemUpdater.Apply(cleared, new UpdateMediaRequest { Status = MediaStatus.InProgress });
        cleared.Status.Should().Be(MediaStatus.InProgress);
        cleared.DropReason.Should().BeNull();
        cleared.DropNotes.Should().BeNull();

        var kept = new Movie { Title = "B", DropReason = "r", DropNotes = "n" };
        MediaItemUpdater.Apply(kept, new UpdateMediaRequest { Status = MediaStatus.Dropped });
        kept.Status.Should().Be(MediaStatus.Dropped);
        kept.DropReason.Should().Be("r"); // a drop keeps its reason
        kept.DropNotes.Should().Be("n");
        kept.IsCustomEdited.Should().BeFalse(); // a status change is not a manual field edit
    }

    [Fact]
    public void Updater_GameAndBook_ShouldApplyTypeSpecificFields()
    {
        var game = new VideoGame { Title = "G", Platform = "old", UserPlatform = "old UP" };
        MediaItemUpdater.Apply(game, new UpdateMediaRequest { Platform = "PC" });
        game.Platform.Should().Be("PC");

        var book = new Book { Title = "B", Author = "old", TotalPages = 10, CurrentPage = 1 };
        MediaItemUpdater.Apply(book, new UpdateMediaRequest
        {
            Author = "Tolkien",
            TotalPages = 300,
            CurrentPage = 25,
        });
        book.Author.Should().Be("Tolkien");
        book.TotalPages.Should().Be(300);
        book.CurrentPage.Should().Be(25);
    }

    [Fact]
    public void Updater_EmptyRequest_ShouldLeaveEverythingAlone()
    {
        var stamp = new DateTime(2025, 5, 5, 0, 0, 0, DateTimeKind.Utc);
        var item = new Book
        {
            Title = "Keep",
            Author = "A",
            Score = 7,
            Notes = "n",
            StartedAt = stamp,
            FinishedAt = stamp,
            Genres = "g",
            Tags = "t",
            DropReason = null,
            DropNotes = null,
        };
        var request = new UpdateMediaRequest();

        MediaItemUpdater.Apply(item, request);

        item.Title.Should().Be("Keep");
        item.Score.Should().Be(7);
        item.Notes.Should().Be("n");
        item.StartedAt.Should().Be(stamp);
        item.FinishedAt.Should().Be(stamp);
        item.Genres.Should().Be("g");
        item.Tags.Should().Be("t");
        item.IsCustomEdited.Should().BeFalse();
    }

    // ---- MediaItemFactory ----

    [Fact]
    public void Factory_Game_ShouldMapFieldsAndSkipAutoRefresh()
    {
        var item = MediaItemFactory.CreateEntity(new CreateMediaRequest
        {
            Type = " GAME ",
            Title = "Elden Ring",
            Platform = "PC",
            HoursPlayed = 40,
            Score = 9,
            Status = MediaStatus.InProgress,
        });

        item.Should().BeOfType<VideoGame>();
        var game = (VideoGame)item;
        game.Platform.Should().Be("PC");
        game.HoursPlayed.Should().Be(40);
        game.Title.Should().Be("Elden Ring");
        game.Score.Should().Be(9);
        item.Status.Should().Be(MediaStatus.InProgress);
        item.NextAutoRefreshAt.Should().BeNull(); // games have nothing a poll could report on
    }

    [Fact]
    public void Factory_Book_ShouldDefaultAuthorAndPages()
    {
        var book = (Book)MediaItemFactory.CreateEntity(new CreateMediaRequest { Type = "book", Title = "Unknown" });

        book.Author.Should().Be(string.Empty);
        book.TotalPages.Should().Be(0);
        book.NextAutoRefreshAt.Should().BeNull();
    }

    [Fact]
    public void Factory_Manga_ShouldScheduleAutoRefresh()
    {
        var manga = (Manga)MediaItemFactory.CreateEntity(new CreateMediaRequest
        {
            Type = "manga",
            Title = "One Piece",
            TotalChapters = 1122,
            TotalVolumes = 105,
            CurrentVolume = 2,
            ReleaseDate = new DateTime(2999, 1, 1),
        });

        manga.TotalChapters.Should().Be(1122);
        manga.TotalVolumes.Should().Be(105);
        manga.CurrentVolume.Should().Be(2);
        manga.ReleaseStatus.Should().Be("NOT_YET_RELEASED");
        manga.AutoRefreshIntervalDays.Should().Be(7);
        manga.NextAutoRefreshAt.Should().NotBeNull();
    }

    [Fact]
    public void Factory_Movie_ShouldDefaultDurationAndAnimeFlag()
    {
        var movie = (Movie)MediaItemFactory.CreateEntity(new CreateMediaRequest
        {
            Type = "Movie",
            Title = "Dune",
            Director = "Villeneuve",
            Studio = "Warner",
            RomajiTitle = "Ro",
        });

        movie.DurationMinutes.Should().Be(0);
        movie.IsAnime.Should().BeFalse();
        movie.Director.Should().Be("Villeneuve");
        movie.Studio.Should().Be("Warner");
        movie.RomajiTitle.Should().Be("Ro");
        movie.ReleaseStatus.Should().BeNull();
    }

    [Fact]
    public void Factory_TvShow_ShouldCreateWithSeasons()
    {
        var airDate = new DateTime(2020, 1, 12);
        var show = (TvShow)MediaItemFactory.CreateEntity(new CreateMediaRequest
        {
            Type = "tvshow",
            Title = "Severance",
            Network = "Apple TV+",
            IsAnime = true,
            Studio = "St",
            RomajiTitle = "Ro",
            DurationMinutes = 60, // EpisodeDurationMinutes absent → movie duration feeds it
            Seasons =
            [
                new CreateSeasonRequest
                {
                    SeasonNumber = 2,
                    Title = "S2",
                    CoverUrl = "c.jpg",
                    TotalEpisodes = 10,
                    Score = 8,
                    Notes = "n",
                    AirDate = airDate,
                    EpisodesData = "ep",
                },
            ],
        });

        show.Network.Should().Be("Apple TV+");
        show.IsAnime.Should().BeTrue();
        show.Studio.Should().Be("St");
        show.RomajiTitle.Should().Be("Ro");
        show.EpisodeDurationMinutes.Should().Be(60);
        show.Seasons.Should().ContainSingle();
        var season = show.Seasons[0];
        season.SeasonNumber.Should().Be(2);
        season.Title.Should().Be("S2");
        season.CoverUrl.Should().Be("c.jpg");
        season.TotalEpisodes.Should().Be(10);
        season.Score.Should().Be(8);
        season.Notes.Should().Be("n");
        season.AirDate.Should().Be(airDate);
        season.EpisodesData.Should().Be("ep");
        season.TvShowId.Should().Be(show.Id);
    }

    [Fact]
    public void Factory_UnknownType_ShouldThrow()
    {
        var act = () => MediaItemFactory.CreateEntity(new CreateMediaRequest { Type = "series", Title = "X" });
        act.Should().Throw<InvalidOperationException>().WithMessage("*series*");
    }

    [Fact]
    public void Factory_ComputeReleaseStatus_ShouldClassifyDates()
    {
        MediaItemFactory.ComputeReleaseStatusFromDates(null, null).Should().BeNull();
        MediaItemFactory.ComputeReleaseStatusFromDates(new DateTime(2001, 1, 1), new DateTime(2002, 1, 1)).Should().Be("FINISHED");
        MediaItemFactory.ComputeReleaseStatusFromDates(new DateTime(2999, 1, 1), null).Should().Be("NOT_YET_RELEASED");
        MediaItemFactory.ComputeReleaseStatusFromDates(new DateTime(2001, 1, 1), null).Should().Be("RELEASING");
    }

    // ---- TvShow entity ----

    private static TvSeason Season(int current, int total) =>
        new() { SeasonNumber = 1, Title = "S", TotalEpisodes = total, CurrentEpisode = current };

    [Fact]
    public void TvShow_SyncStatus_AllSeasonsCompleted_ShouldComplete()
    {
        var stamp = new DateTime(2026, 2, 2, 0, 0, 0, DateTimeKind.Utc);
        var show = new TvShow { Title = "S", Status = MediaStatus.InProgress, StartedAt = new DateTime(2025, 1, 1), FinishedAt = new DateTime(2026, 1, 1) };
        show.Seasons.Add(Season(10, 10));
        show.Seasons.Add(Season(5, 5));

        show.SyncStatusFromSeasons(stamp);

        show.Status.Should().Be(MediaStatus.Completed);
        show.StartedAt.Should().Be(new DateTime(2025, 1, 1));
        show.FinishedAt.Should().Be(new DateTime(2026, 1, 1)); // stored stamp wins over "now"
        show.TotalEpisodesWatched.Should().Be(15);
        show.TotalEpisodesCount.Should().Be(15);
        show.AllSeasonsCompleted.Should().BeTrue();
    }

    [Fact]
    public void TvShow_SyncStatus_WatchedEpisodes_ShouldMoveToInProgress()
    {
        var stamp = new DateTime(2026, 2, 2, 0, 0, 0, DateTimeKind.Utc);

        // Completed row with un-watched seasons never keeps the completed badge
        var completed = new TvShow { Title = "C", Status = MediaStatus.Completed };
        completed.Seasons.Add(Season(3, 10));
        completed.SyncStatusFromSeasons(stamp);
        completed.Status.Should().Be(MediaStatus.InProgress);
        completed.StartedAt.Should().Be(stamp);
        completed.FinishedAt.Should().BeNull();

        // Planned → in progress
        var planned = new TvShow { Title = "P", Status = MediaStatus.Planned, FinishedAt = stamp };
        planned.Seasons.Add(Season(1, 10));
        planned.SyncStatusFromSeasons(stamp);
        planned.Status.Should().Be(MediaStatus.InProgress);
        planned.FinishedAt.Should().BeNull();

        // OnHold → already mid-lifecycle, the watched check only stamps the start
        var onHold = new TvShow { Title = "H", Status = MediaStatus.OnHold };
        onHold.Seasons.Add(Season(2, 10));
        onHold.SyncStatusFromSeasons(stamp);
        onHold.Status.Should().Be(MediaStatus.OnHold);
        onHold.StartedAt.Should().Be(stamp);
        onHold.FinishedAt.Should().BeNull();
    }

    [Fact]
    public void TvShow_SyncStatus_NoWatchedEpisodes_ShouldRewindToPlanned()
    {
        var stamp = new DateTime(2026, 2, 2, 0, 0, 0, DateTimeKind.Utc);

        var inProgress = new TvShow { Title = "A", Status = MediaStatus.InProgress, StartedAt = stamp, FinishedAt = stamp };
        inProgress.Seasons.Add(Season(0, 10));
        inProgress.SyncStatusFromSeasons(stamp);
        inProgress.Status.Should().Be(MediaStatus.Planned);
        inProgress.StartedAt.Should().BeNull();
        inProgress.FinishedAt.Should().BeNull();

        // Already planned: stays planned; an empty season list keeps AllSeasonsCompleted false
        var planned = new TvShow { Title = "B", Status = MediaStatus.Planned, StartedAt = stamp };
        planned.SyncStatusFromSeasons(stamp);
        planned.Status.Should().Be(MediaStatus.Planned);
        planned.StartedAt.Should().BeNull();
        planned.AllSeasonsCompleted.Should().BeFalse();
        show_SumTotalsOfEmptyListsAreZero(planned);
    }

    private void show_SumTotalsOfEmptyListsAreZero(TvShow show)
    {
        show.TotalEpisodesWatched.Should().Be(0);
        show.TotalEpisodesCount.Should().Be(0);
    }

    [Fact]
    public void TvShow_ChangeStatus_ShouldRollOntoSeasons()
    {
        var show = new TvShow { Title = "S" };
        show.Seasons.Add(Season(2, 10));
        show.Seasons.Add(Season(10, 10));

        show.ChangeStatus(MediaStatus.Completed);
        show.Status.Should().Be(MediaStatus.Completed);
        show.Seasons[0].CurrentEpisode.Should().Be(10);
        show.Seasons[0].Status.Should().Be(MediaStatus.Completed);
        show.Seasons[1].CurrentEpisode.Should().Be(10);

        show.ChangeStatus(MediaStatus.Planned, new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        show.Status.Should().Be(MediaStatus.Planned);
        show.Seasons[0].CurrentEpisode.Should().Be(0);
        show.Seasons.Select(s => (int)s.Status).Should().OnlyContain(s => s == (int)MediaStatus.Planned);
    }

    // ---- GlobalExceptionHandler ----

    private sealed class FakeEnvironment(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;
        public string ApplicationName { get; set; } = "test";
        public string ContentRootPath { get; set; } = "/";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private static (int StatusCode, string? ContentType, ProblemDetails Problem) RunHandler(
        GlobalExceptionHandler handler, Exception exception)
    {
        var context = new DefaultHttpContext();
        var body = new MemoryStream();
        context.Response.Body = body;

        context.Request.Path = "/api/test";
        var handled = handler.TryHandleAsync(context, exception, CancellationToken.None).GetAwaiter().GetResult();
        handled.Should().BeTrue();

        body.Position = 0;
        var problem = JsonSerializer.Deserialize<ProblemDetails>(
            new StreamReader(body).ReadToEnd(), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        return (context.Response.StatusCode, context.Response.ContentType, problem);
    }

    [Fact]
    public async Task Handler_SourceUnavailable_ShouldWrite502Problem()
    {
        var handler = new GlobalExceptionHandler(
            NullLogger<GlobalExceptionHandler>.Instance,
            new FakeEnvironment("Development"));
        var inner = new HttpRequestException("socket closed");
        var exception = new SourceUnavailableException("tmdb", "upstream down", inner);

        var (status, contentType, problem) = RunHandler(handler, exception);

        status.Should().Be(StatusCodes.Status502BadGateway);
        contentType.Should().Be("application/problem+json");
        problem.Title.Should().Be("External metadata source is unavailable.");
        problem.Status.Should().Be(502);
        problem.Instance.Should().Be("/api/test");
        problem.Detail.Should().NotBeNullOrWhiteSpace(); // Development hides nothing
    }

    [Fact]
    public async Task Handler_UnhandledException_Production_ShouldHideDetail()
    {
        var handler = new GlobalExceptionHandler(
            NullLogger<GlobalExceptionHandler>.Instance,
            new FakeEnvironment("Production"));

        var (status, contentType, problem) = RunHandler(handler, new InvalidOperationException("boom"));

        status.Should().Be(StatusCodes.Status500InternalServerError);
        contentType.Should().Be("application/problem+json");
        problem.Title.Should().Be("An unexpected error occurred.");
        problem.Detail.Should().BeNull();
    }
}
