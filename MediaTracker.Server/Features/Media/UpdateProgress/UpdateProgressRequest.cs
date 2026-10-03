namespace MediaTracker.Server.Features.Media.UpdateProgress;

public sealed record UpdateProgressRequest
{
    public required int CurrentProgress { get; init; }
}
