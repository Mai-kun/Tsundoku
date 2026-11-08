using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Background auto-refresh cadence. Ongoings (manga, shows, anime) are polled on an adaptive
/// interval that stretches while nothing new is published and snaps back to the base interval the
/// moment new content appears, so a slow series quietly checks every month while an active one
/// gets its daily attention back within a week.
/// </summary>
public static class AutoRefreshRules
{
    public const int BaseIntervalDays = 7;

    public const int MaxIntervalDays = 30;

    public const int HiatusIntervalDays = 45;

    /// <summary>
    /// Only titles whose source keeps publishing new material deserve a poll: dropped rows and
    /// officially finished releases never change. Books and games are excluded outright — a game
    /// library does not change upstream the way an airing season does, and a book's content is
    /// fixed, so the scheduler never picks them up no matter what the row's status says.
    /// </summary>
    public static bool ShouldScheduleRefresh(MediaItem item) =>
        item is not VideoGame
        && item is not Book
        && item.Status != MediaStatus.Dropped
        && !IsFinished(item)
        && item is Manga or TvShow or Movie { IsAnime: true };

    /// <summary>
    /// One progression step for a poll that found nothing new: 7 → 10 → 14 → 21 → 30, and a hiatus
    /// stretches the base out to 45 days because no author publishes during one anyway.
    /// </summary>
    public static int CalculateNextInterval(int currentInterval, bool hasNewContent, string? releaseStatus)
    {
        if (string.Equals(ReleaseStatusRules.NormalizeStatus(releaseStatus), ReleaseStatusRules.Hiatus, StringComparison.OrdinalIgnoreCase))
        {
            return HiatusIntervalDays;
        }

        if (hasNewContent)
        {
            return BaseIntervalDays;
        }

        return currentInterval switch
        {
            < 10 => 10,
            < 14 => 14,
            < 21 => 21,
            _ => MaxIntervalDays,
        };
    }

    /// <summary>
    /// Writes the next check date onto the item. A finished release gets no further check, so the
    /// scheduler stops picking the row up at all.
    /// </summary>
    public static void ApplyRefreshSchedule(MediaItem item, bool hasNewContent, DateTime now)
    {
        if (IsFinished(item))
        {
            item.NextAutoRefreshAt = null;
            return;
        }

        item.AutoRefreshIntervalDays = CalculateNextInterval(item.AutoRefreshIntervalDays, hasNewContent, item.ReleaseStatus);
        item.LastAutoRefreshedAt = now;
        item.NextAutoRefreshAt = now.AddDays(item.AutoRefreshIntervalDays);
    }

    /// <summary>
    /// "Finished" in every source's spelling — Shikimori's RELEASED counts the same as AniList's
    /// FINISHED. A literal comparison here is what kept scheduling completed anime forever.
    /// </summary>
    private static bool IsFinished(MediaItem item) =>
        ReleaseStatusRules.IsFinishedStatus(item.ReleaseStatus);
}
