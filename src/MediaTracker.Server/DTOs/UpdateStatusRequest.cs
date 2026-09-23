using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public sealed record UpdateStatusRequest
{
    public required MediaStatus Status { get; init; }
}