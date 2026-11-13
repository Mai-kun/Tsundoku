using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using Xunit;

namespace MediaTracker.Tests;

public class DomainRulesTests
{
    [Fact]
    public void ProgressStepperRules_Clamp_ShouldEnforceBoundsCorrectly()
    {
        ProgressStepperRules.Clamp(5, 12).Should().Be(5);
        ProgressStepperRules.Clamp(15, 12).Should().Be(12);
        ProgressStepperRules.Clamp(-3, 12).Should().Be(0);
        // When total is 0 or unknown, it does not clamp upper bound
        ProgressStepperRules.Clamp(25, 0).Should().Be(25);
        ProgressStepperRules.Clamp(-5, 0).Should().Be(0);
    }

    [Fact]
    public void ProgressStepperRules_PromotesToInProgress_ShouldFireOnlyOnExactZeroToOne()
    {
        // Rule 1: only the exact 0 -> 1 step implies the title started.
        ProgressStepperRules.PromotesToInProgress(0, 1).Should().BeTrue();

        // Every other progress change keeps the current status.
        ProgressStepperRules.PromotesToInProgress(0, 5).Should().BeFalse();
        ProgressStepperRules.PromotesToInProgress(1, 2).Should().BeFalse();
        ProgressStepperRules.PromotesToInProgress(3, 4).Should().BeFalse();
        ProgressStepperRules.PromotesToInProgress(5, 4).Should().BeFalse();
        ProgressStepperRules.PromotesToInProgress(3, 0).Should().BeFalse();
        ProgressStepperRules.PromotesToInProgress(2, 0).Should().BeFalse();
    }

    [Fact]
    public void ChangeStatus_LeavingCompleted_ShouldResetProgress()
    {
        // Rule 2: Completed -> any other status is the only status change that resets progress.
        var book = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300, CurrentChapter = 21 };
        book.ChangeStatus(MediaStatus.Completed);

        book.ChangeStatus(MediaStatus.Planned);
        book.CurrentPage.Should().Be(0);
        book.CurrentChapter.Should().Be(0);
        book.Status.Should().Be(MediaStatus.Planned);

        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC", HoursPlayed = 42 };
        game.ChangeStatus(MediaStatus.Completed);
        game.ChangeStatus(MediaStatus.OnHold);
        game.HoursPlayed.Should().Be(0);

        var manga = new Manga { Title = "One Piece", TotalChapters = 1100, CurrentChapter = 950 };
        manga.ChangeStatus(MediaStatus.Completed);
        manga.ChangeStatus(MediaStatus.Dropped);
        manga.CurrentChapter.Should().Be(0);
        manga.CurrentVolume.Should().Be(0);
    }

    [Fact]
    public void ChangeStatus_NotLeavingCompleted_ShouldKeepProgress()
    {
        // InProgress -> Planned keeps the counters: no hidden reset outside rule 2.
        var book = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300, CurrentChapter = 21, Status = MediaStatus.InProgress };
        book.ChangeStatus(MediaStatus.Planned);
        book.CurrentPage.Should().Be(300);
        book.CurrentChapter.Should().Be(21);

        // Planned -> OnHold keeps them, OnHold -> Planned keeps them.
        var game = new VideoGame { Title = "Elden Ring", Platform = "PC", HoursPlayed = 17, Status = MediaStatus.Planned };
        game.ChangeStatus(MediaStatus.OnHold);
        game.HoursPlayed.Should().Be(17);
        game.ChangeStatus(MediaStatus.Planned);
        game.HoursPlayed.Should().Be(17);

        // Dropped -> Planned keeps them too.
        var manga = new Manga { Title = "Bleach", CurrentChapter = 340, CurrentVolume = 30, Status = MediaStatus.Dropped };
        manga.ChangeStatus(MediaStatus.Planned);
        manga.CurrentChapter.Should().Be(340);
        manga.CurrentVolume.Should().Be(30);

        // Completed -> Completed is a no-op for the counters as well.
        var finished = new Book { Title = "Dune Messiah", Author = string.Empty, TotalPages = 256, CurrentPage = 256 };
        finished.ChangeStatus(MediaStatus.Completed);
        finished.ChangeStatus(MediaStatus.Completed);
        finished.CurrentPage.Should().Be(256);
    }

    [Fact]
    public void TvShow_ChangeStatus_LeavingCompleted_ShouldRollResetOntoSeasons()
    {
        var show = new TvShow { Title = "Naruto", Status = MediaStatus.Completed };
        show.Seasons.Add(new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 220, CurrentEpisode = 110, Status = MediaStatus.InProgress });
        show.Seasons.Add(new TvSeason { SeasonNumber = 2, Title = "S2", TotalEpisodes = 24, CurrentEpisode = 24, Status = MediaStatus.Completed });

        show.ChangeStatus(MediaStatus.Planned);

        show.Status.Should().Be(MediaStatus.Planned);
        show.TotalEpisodesWatched.Should().Be(0);
        show.Seasons[0].CurrentEpisode.Should().Be(0);
        show.Seasons[0].Status.Should().Be(MediaStatus.Planned);
        show.Seasons[1].CurrentEpisode.Should().Be(0);
        show.Seasons[1].Status.Should().Be(MediaStatus.Planned);
    }

    [Fact]
    public void TvShow_ChangeStatus_NotLeavingCompleted_ShouldKeepSeasons()
    {
        // InProgress -> Planned keeps the watched episodes on every season.
        var show = new TvShow { Title = "Frieren", Status = MediaStatus.InProgress };
        show.Seasons.Add(new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 28, CurrentEpisode = 12, Status = MediaStatus.InProgress });

        show.ChangeStatus(MediaStatus.Planned);
        show.TotalEpisodesWatched.Should().Be(12);
        show.Seasons[0].Status.Should().Be(MediaStatus.InProgress);

        // Planned -> OnHold keeps them; OnHold -> Dropped keeps them.
        show.ChangeStatus(MediaStatus.OnHold);
        show.TotalEpisodesWatched.Should().Be(12);
        show.ChangeStatus(MediaStatus.Dropped);
        show.TotalEpisodesWatched.Should().Be(12);

        // Completed -> Completed does not touch the seasons either.
        show.ChangeStatus(MediaStatus.Completed);
        show.ChangeStatus(MediaStatus.Completed);
        show.TotalEpisodesWatched.Should().Be(12);
    }

    [Fact]
    public void AutoRefreshRules_CalculateNextInterval_ShouldFollowProgressionAndHiatus()
    {
        // Progression when no new content: 7 -> 10 -> 14 -> 21 -> 30
        AutoRefreshRules.CalculateNextInterval(7, hasNewContent: false, releaseStatus: null).Should().Be(10);
        AutoRefreshRules.CalculateNextInterval(10, hasNewContent: false, releaseStatus: null).Should().Be(14);
        AutoRefreshRules.CalculateNextInterval(14, hasNewContent: false, releaseStatus: null).Should().Be(21);
        AutoRefreshRules.CalculateNextInterval(21, hasNewContent: false, releaseStatus: null).Should().Be(30);
        AutoRefreshRules.CalculateNextInterval(30, hasNewContent: false, releaseStatus: null).Should().Be(30);

        // When new content arrives, snaps back to BaseIntervalDays (7)
        AutoRefreshRules.CalculateNextInterval(30, hasNewContent: true, releaseStatus: null).Should().Be(7);
        AutoRefreshRules.CalculateNextInterval(21, hasNewContent: true, releaseStatus: null).Should().Be(7);

        // Hiatus stretches to 45
        AutoRefreshRules.CalculateNextInterval(7, hasNewContent: false, releaseStatus: "HIATUS").Should().Be(45);
        AutoRefreshRules.CalculateNextInterval(30, hasNewContent: true, releaseStatus: "hiatus").Should().Be(45);
    }

    [Fact]
    public void AutoRefreshRules_ShouldScheduleRefresh_ShouldFilterAppropriateTypesAndStatuses()
    {
        var ongoingManga = new Manga { Title = "Ongoing Manga", Status = MediaStatus.InProgress, ReleaseStatus = "RELEASING" };
        var finishedManga = new Manga { Title = "Finished Manga", Status = MediaStatus.Completed, ReleaseStatus = ReleaseStatusRules.Finished };
        var droppedManga = new Manga { Title = "Dropped Manga", Status = MediaStatus.Dropped, ReleaseStatus = "RELEASING" };
        var animeMovie = new Movie { Title = "Anime Movie", IsAnime = true, Status = MediaStatus.InProgress, ReleaseStatus = "RELEASING" };
        var normalMovie = new Movie { Title = "Live Movie", IsAnime = false, Status = MediaStatus.InProgress, ReleaseStatus = "RELEASING" };
        var game = new VideoGame { Title = "Elden Ring", Platform = "PC", Status = MediaStatus.InProgress };

        AutoRefreshRules.ShouldScheduleRefresh(ongoingManga).Should().BeTrue();
        AutoRefreshRules.ShouldScheduleRefresh(animeMovie).Should().BeTrue();
        AutoRefreshRules.ShouldScheduleRefresh(finishedManga).Should().BeFalse();
        AutoRefreshRules.ShouldScheduleRefresh(droppedManga).Should().BeFalse();
        AutoRefreshRules.ShouldScheduleRefresh(normalMovie).Should().BeFalse();
        AutoRefreshRules.ShouldScheduleRefresh(game).Should().BeFalse();
    }

    [Fact]
    public void AutoRefreshRules_ApplyRefreshSchedule_ShouldUpdateIntervalAndDates()
    {
        var now = new DateTime(2026, 3, 15, 12, 0, 0, DateTimeKind.Utc);
        var manga = new Manga { Title = "Test Manga", AutoRefreshIntervalDays = 7, ReleaseStatus = "RELEASING" };

        AutoRefreshRules.ApplyRefreshSchedule(manga, hasNewContent: false, now);

        manga.AutoRefreshIntervalDays.Should().Be(10);
        manga.LastAutoRefreshedAt.Should().Be(now);
        manga.NextAutoRefreshAt.Should().Be(now.AddDays(10));

        // When finished, NextAutoRefreshAt becomes null
        manga.ReleaseStatus = ReleaseStatusRules.Finished;
        AutoRefreshRules.ApplyRefreshSchedule(manga, hasNewContent: false, now);
        manga.NextAutoRefreshAt.Should().BeNull();
    }

    [Fact]
    public void ReleaseStatusRules_FromDates_ShouldDeriveStatusFromDates()
    {
        var today = new DateTime(2026, 6, 1, 0, 0, 0, DateTimeKind.Utc);

        // Past end date -> FINISHED
        ReleaseStatusRules.FromDates(new DateTime(2025, 1, 1), new DateTime(2026, 5, 1), today)
            .Should().Be(ReleaseStatusRules.Finished);

        // Future start date -> NOT_YET_RELEASED
        ReleaseStatusRules.FromDates(new DateTime(2026, 7, 1), null, today)
            .Should().Be(ReleaseStatusRules.NotYetReleased);

        // Past start date, no end date -> RELEASING
        ReleaseStatusRules.FromDates(new DateTime(2026, 1, 1), null, today)
            .Should().Be(ReleaseStatusRules.Releasing);

        // No dates -> null
        ReleaseStatusRules.FromDates(null, null, today).Should().BeNull();
    }

    [Fact]
    public void MangaFormats_ShouldResolveByCountryAndLanguage()
    {
        MangaFormats.FromCountryOfOrigin("KR").Should().Be(MangaFormats.Manhwa);
        MangaFormats.FromCountryOfOrigin("CN").Should().Be(MangaFormats.Manhua);
        MangaFormats.FromCountryOfOrigin("JP").Should().Be(MangaFormats.Manga);
        MangaFormats.FromCountryOfOrigin("US").Should().BeNull();

        MangaFormats.FromOriginalLanguage("EN").Should().Be(MangaFormats.Oel);
        MangaFormats.FromOriginalLanguage("KO").Should().Be(MangaFormats.Manhwa);
        MangaFormats.FromOriginalLanguage("ZH").Should().Be(MangaFormats.Manhua);
        MangaFormats.FromOriginalLanguage("JA").Should().Be(MangaFormats.Manga);
        MangaFormats.FromOriginalLanguage("FR").Should().BeNull();

        // OEL preference
        MangaFormats.Pick("manga", "oel").Should().Be(MangaFormats.Oel);
        MangaFormats.Pick("manhwa", "manga").Should().Be("manhwa");
        MangaFormats.Pick("", "manhua").Should().Be("manhua");

        // Enum conversions
        MangaFormats.ToEnum("manhwa").Should().Be(MangaFormat.Manhwa);
        MangaFormats.ToEnum("manhua").Should().Be(MangaFormat.Manhua);
        MangaFormats.ToEnum("oel").Should().Be(MangaFormat.Oel);
        MangaFormats.ToEnum("manga").Should().Be(MangaFormat.Manga);
        MangaFormats.ToEnum("unknown").Should().BeNull();
    }
}
