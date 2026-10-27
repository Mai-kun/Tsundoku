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
    public void ProgressStepperRules_ResolveEpisodeStatus_ShouldDetermineCorrectStatus()
    {
        ProgressStepperRules.ResolveEpisodeStatus(0, 12).Should().Be(MediaStatus.Planned);
        ProgressStepperRules.ResolveEpisodeStatus(5, 12).Should().Be(MediaStatus.InProgress);
        ProgressStepperRules.ResolveEpisodeStatus(12, 12).Should().Be(MediaStatus.Completed);
    }

    [Fact]
    public void ProgressStepperRules_ResolveVolumeStatus_ShouldDetermineCorrectStatus()
    {
        ProgressStepperRules.ResolveVolumeStatus(0, 200, 0, 10).Should().Be(MediaStatus.Planned);
        ProgressStepperRules.ResolveVolumeStatus(50, 200, 0, 10).Should().Be(MediaStatus.InProgress);
        ProgressStepperRules.ResolveVolumeStatus(0, 200, 5, 10).Should().Be(MediaStatus.InProgress);
        ProgressStepperRules.ResolveVolumeStatus(200, 200, 10, 10).Should().Be(MediaStatus.Completed);
    }

    [Fact]
    public void ProgressStepperRules_ResolveShowStatus_ShouldHandleRollupAndRewinds()
    {
        var started = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var now = new DateTime(2026, 2, 2, 0, 0, 0, DateTimeKind.Utc);

        // 1. All seasons completed
        var allDone = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.InProgress,
            started,
            null,
            allCompleted: true,
            anyWatched: true,
            now);

        allDone.Status.Should().Be(MediaStatus.Completed);
        allDone.StartedAt.Should().Be(started);
        allDone.FinishedAt.Should().Be(now);

        // 2. Part of show watched -> InProgress
        var inProgress = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.Planned,
            null,
            null,
            allCompleted: false,
            anyWatched: true,
            now);

        inProgress.Status.Should().Be(MediaStatus.InProgress);
        inProgress.StartedAt.Should().Be(now);
        inProgress.FinishedAt.Should().BeNull();

        // 3. Rewind across season boundary -> rewind to Planned
        var rewound = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.Completed,
            started,
            now,
            allCompleted: false,
            anyWatched: false,
            now);

        rewound.Status.Should().Be(MediaStatus.Planned);
        rewound.StartedAt.Should().BeNull();
        rewound.FinishedAt.Should().BeNull();
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
