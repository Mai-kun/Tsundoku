using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.UpdateStatus;

public sealed record UpdateStatusRequest
{
    public required MediaStatus Status { get; init; }

    public string? DropReason { get; init; }

    public string? DropNotes { get; init; }
}
