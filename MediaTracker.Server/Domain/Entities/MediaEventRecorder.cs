using MediaTracker.Server.Domain.Enums;

namespace MediaTracker.Server.Domain.Entities;

/// <summary>
/// Appends rows to the activity log. Callers pass the before/after they already have in hand, so
/// this never re-queries the item and never decides on its own what counts as a change.
/// </summary>
public static class MediaEventRecorder
{
    public static MediaEvent Added(MediaItem item) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.Added,
            NewValue = item.Title
        };

    public static MediaEvent StatusChanged(MediaItem item, MediaStatus from, MediaStatus to) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.StatusChanged,
            OldValue = from.ToString(),
            NewValue = to.ToString()
        };

    public static MediaEvent ScoreChanged(MediaItem item, int? from, int? to) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.ScoreChanged,
            OldValue = from?.ToString(),
            NewValue = to?.ToString()
        };

    public static MediaEvent ProgressChanged(MediaItem item, string? from, string? to) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.ProgressChanged,
            OldValue = from,
            NewValue = to
        };

    public static MediaEvent Deleted(MediaItem item) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.Deleted,
            OldValue = item.Title
        };

    public static MediaEvent AchievementUnlocked(MediaItem item, string name) =>
        new()
        {
            MediaId = item.Id,
            Type = MediaEventType.AchievementUnlocked,
            NewValue = name
        };
}
