namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// The wire shape of one background task. It is both the entry stored in the registry and the SSE
/// payload, so the browser can render the very same object it would have received from GET /api/jobs.
/// </summary>
public sealed record JobProgressDto(
    Guid JobId,
    Guid? MediaId,
    string Title,
    int ProgressPercent,
    string CurrentStep,
    JobStatus Status,
    DateTime StartedAt,
    string? ErrorMessage);