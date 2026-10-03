using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.UpdateStatus;

public sealed record UpdateStatusRequest
{
    public required MediaStatus Status { get; init; }
}
