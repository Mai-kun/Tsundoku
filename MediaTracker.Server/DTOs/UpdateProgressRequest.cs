namespace MediaTracker.Server.DTOs;

public sealed record UpdateProgressRequest
{
    public required int CurrentProgress { get; init; }
}