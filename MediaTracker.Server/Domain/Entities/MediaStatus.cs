namespace MediaTracker.Server.Domain.Entities;

/// <summary>
/// The lifecycle of a tracked item. The numeric values are part of the wire contract: the UI sends and
/// reads 0..4 and its status maps are keyed on those literals, so the order must not change.
/// </summary>
public enum MediaStatus
{
    Planned = 0,
    InProgress = 1,
    Completed = 2,
    OnHold = 3,
    Dropped = 4,
}
