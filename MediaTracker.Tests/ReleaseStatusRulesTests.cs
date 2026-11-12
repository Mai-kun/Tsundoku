using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// The canonical release-status fold: Shikimori's "released" must read as finished by the
/// auto-refresh rules, and already-migrated rows must be repaired on startup.
/// </summary>
public class ReleaseStatusRulesTests
{
    [Theory]
    [InlineData("FINISHED", "FINISHED")]
    [InlineData("RELEASED", "FINISHED")]
    [InlineData("released", "FINISHED")]
    [InlineData("Ended", "FINISHED")]
    [InlineData("ЗАВЕРШЁН", "FINISHED")]
    [InlineData("RELEASING", "RELEASING")]
    [InlineData("ongoing", "RELEASING")]
    [InlineData("AIRING", "RELEASING")]
    [InlineData("anons", "NOT_YET_RELEASED")]
    [InlineData("NOT_YET_RELEASED", "NOT_YET_RELEASED")]
    [InlineData("paused", "HIATUS")]
    [InlineData("ЗАМОРОЖЕН", "HIATUS")]
    [InlineData("canceled", "CANCELLED")]
    [InlineData("DISCONTINUED", "CANCELLED")]
    public void NormalizeStatus_ShouldFoldEverySourceVocabulary(string raw, string expected) =>
        ReleaseStatusRules.NormalizeStatus(raw).Should().Be(expected);

    [Fact]
    public void NormalizeStatus_ShouldPreserveUnknownFreeTextVerbatim() =>
        ReleaseStatusRules.NormalizeStatus("Created ReleaseStatus").Should().Be("Created ReleaseStatus");

    [Fact]
    public void NormalizeStatus_ShouldReturnNullForBlank() =>
        ReleaseStatusRules.NormalizeStatus("   ").Should().BeNull();

    [Theory]
    [InlineData("RELEASED", true)]
    [InlineData("finished", true)]
    [InlineData("Завершено", true)]
    [InlineData("RELEASING", false)]
    [InlineData("ONGOING", false)]
    [InlineData(null, false)]
    public void IsFinishedStatus_ShouldRecognizeFinishedInEverySpelling(string? status, bool expected) =>
        ReleaseStatusRules.IsFinishedStatus(status).Should().Be(expected);

    [Fact]
    public void ShouldScheduleRefresh_ShouldSkipReleasedShikimoriRows()
    {
        var item = new TvShow { Title = "Noragami", IsAnime = true, ReleaseStatus = "RELEASED" };
        AutoRefreshRules.ShouldScheduleRefresh(item).Should().BeFalse();
    }

    [Fact]
    public void ApplyRefreshSchedule_ShouldClearNextAutoRefreshForReleasedItems()
    {
        var item = new TvShow
        {
            Title = "Бездомный бог",
            IsAnime = true,
            ReleaseStatus = "RELEASED",
            AutoRefreshIntervalDays = 7,
            NextAutoRefreshAt = DateTime.UtcNow.AddDays(3),
        };
        var before = item.LastAutoRefreshedAt;

        AutoRefreshRules.ApplyRefreshSchedule(item, hasNewContent: false, DateTime.UtcNow);

        item.NextAutoRefreshAt.Should().BeNull();
        item.LastAutoRefreshedAt.Should().Be(before);
    }

    [Fact]
    public void ApplyRefreshSchedule_ShouldStillScheduleOngoings()
    {
        var item = new TvShow { Title = "Онгоинг", IsAnime = true, ReleaseStatus = "RELEASING" };

        AutoRefreshRules.ApplyRefreshSchedule(item, hasNewContent: false, DateTime.UtcNow);

        item.NextAutoRefreshAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Migration_ShouldCanonicalizeLegacyReleasedRows()
    {
        using var db = new AppDbContext($"Data Source={Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.db")}");
        db.Database.EnsureCreated();

        db.MediaItems.AddRange(
            new TvShow { Title = "Legacy Shikimori", IsAnime = true, ReleaseStatus = "RELEASED", NextAutoRefreshAt = DateTime.UtcNow.AddDays(2) },
            new Manga { Title = "Legacy Finished", ReleaseStatus = "finished", NextAutoRefreshAt = DateTime.UtcNow.AddDays(2) },
            new TvShow { Title = "Legacy Russian", IsAnime = true, ReleaseStatus = "Завершён", NextAutoRefreshAt = DateTime.UtcNow.AddDays(2) },
            new TvShow { Title = "Ongoing Untouched", IsAnime = true, ReleaseStatus = "RELEASING", NextAutoRefreshAt = DateTime.UtcNow.AddDays(2) });
        await db.SaveChangesAsync();

        // Legacy databases carry no schema stamp; migrations now run on that upgrade instead of on
        // every database call, so simulate a pre-versioning file before the next call.
        using (var cmd = db.Connection.CreateCommand())
        {
            cmd.CommandText = "PRAGMA user_version = 0;";
            await cmd.ExecuteNonQueryAsync();
        }

        // Any later db call on the un-stamped file runs the startup migration on the saved rows.
        await db.LoadMediaItemsAsync(null, null, null, null, null, null, CancellationToken.None);

        var rows = db.MediaItems.ToList();
        rows.Single(m => m.Title == "Legacy Shikimori").ReleaseStatus.Should().Be("FINISHED");
        rows.Single(m => m.Title == "Legacy Shikimori").NextAutoRefreshAt.Should().BeNull();
        rows.Single(m => m.Title == "Legacy Finished").ReleaseStatus.Should().Be("FINISHED");
        rows.Single(m => m.Title == "Legacy Finished").NextAutoRefreshAt.Should().BeNull();
        rows.Single(m => m.Title == "Legacy Russian").ReleaseStatus.Should().Be("FINISHED");
        rows.Single(m => m.Title == "Legacy Russian").NextAutoRefreshAt.Should().BeNull();
        rows.Single(m => m.Title == "Ongoing Untouched").ReleaseStatus.Should().Be("RELEASING");
        rows.Single(m => m.Title == "Ongoing Untouched").NextAutoRefreshAt.Should().NotBeNull();
    }
}
