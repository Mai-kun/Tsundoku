namespace MediaTracker.Server.Domain.Enums;

/// <summary>
/// Whether the background enrichment of a freshly added title has finished. Kept off
/// <c>MediaStatus</c> on purpose: tracking progress ("watching") is what that enum means, this one
/// only tells the UI that the poster and the season list are still being filled in.
/// </summary>
public enum SyncStatus
{
    Ready = 0,
    Syncing = 1,
    Failed = 2,
}