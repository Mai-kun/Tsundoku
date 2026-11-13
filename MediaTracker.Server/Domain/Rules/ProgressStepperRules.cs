namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// The strict status/progress contract shared by every progress write path. Exactly two automatic
/// transitions exist and nothing else may touch status or progress implicitly:
/// <list type="bullet">
/// <item>Rule 1 — progress moving exactly 0 → 1 promotes the title to <c>InProgress</c>; any other
/// progress change keeps the current status (a dropped title stays dropped, on hold stays on hold).</item>
/// <item>Rule 2 — leaving <c>Completed</c> resets the counters to zero; every other status change
/// keeps the progress (implemented by <see cref="Entities.MediaItem.ChangeStatus"/>).</item>
/// </list>
/// </summary>
public static class ProgressStepperRules
{
    public static int Clamp(int value, int total) =>
        total > 0 ? Math.Min(Math.Max(value, 0), total) : Math.Max(value, 0);

    /// <summary>Rule 1: only the exact 0 → 1 step implies the title is being consumed right now.</summary>
    public static bool PromotesToInProgress(int oldProgress, int newProgress) =>
        oldProgress == 0 && newProgress == 1;
}
