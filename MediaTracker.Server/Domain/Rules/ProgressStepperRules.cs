namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// The clamps and verdicts behind every progress stepper. They live in the domain because they decide
/// business state (planned / in progress / completed) from raw counters, not because they format
/// anything. The stepper writes bypass the change tracker, so the entity methods delegate here.
/// </summary>
public static class ProgressStepperRules
{
    public static int Clamp(int value, int total) =>
        total > 0 ? Math.Min(Math.Max(value, 0), total) : Math.Max(value, 0);

    public static Entities.MediaStatus ResolveEpisodeStatus(int currentEpisode, int totalEpisodes) =>
        Entities.TvSeason.ResolveStatus(currentEpisode, totalEpisodes);

    public static Entities.MediaStatus ResolveVolumeStatus(
        int currentPage,
        int totalPages,
        int currentChapter,
        int totalChapters) =>
        Entities.MangaVolume.ResolveStatus(currentPage, totalPages, currentChapter, totalChapters);

    /// <summary>
    /// Rolls the season totals up onto the parent show. Mirrors the per-season rules so a show never
    /// keeps a "completed" badge with un-watched seasons.
    /// </summary>
    public static (Entities.MediaStatus Status, DateTime? StartedAt, DateTime? FinishedAt) ResolveShowStatus(
        Entities.MediaStatus currentStatus,
        DateTime? currentStartedAt,
        DateTime? currentFinishedAt,
        bool allCompleted,
        bool anyWatched,
        DateTime now)
    {
        if (allCompleted)
        {
            return (Entities.MediaStatus.Completed, currentStartedAt ?? now, currentFinishedAt ?? now);
        }

        if (anyWatched)
        {
            return (
                currentStatus is Entities.MediaStatus.Completed or Entities.MediaStatus.Planned
                    ? Entities.MediaStatus.InProgress
                    : currentStatus,
                currentStartedAt ?? now,
                null);
        }

        return (
            currentStatus is Entities.MediaStatus.InProgress or Entities.MediaStatus.Completed
                ? Entities.MediaStatus.Planned
                : currentStatus,
            null,
            null);
    }
}
