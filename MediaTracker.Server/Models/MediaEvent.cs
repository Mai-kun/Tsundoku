namespace MediaTracker.Server.Models;

/// <summary>
/// What happened to a tracked item and when. The history screen reads this table; the previous
/// behaviour (deriving "started"/"finished" from two date columns) could not show a status change,
/// a rating change, or the act of adding something.
/// </summary>
public class MediaEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public required Guid MediaId { get; set; }

    public MediaItem? Media { get; set; }

    public required MediaEventType Type { get; set; }

    /// <summary>Previous value, rendered as text. Null when the event has no "before".</summary>
    public string? OldValue { get; set; }

    /// <summary>New value, rendered as text. Null when the event has no "after".</summary>
    public string? NewValue { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public enum MediaEventType
{
    Added,
    StatusChanged,
    ScoreChanged,
    ProgressChanged,
    Deleted,
    AchievementUnlocked,
}