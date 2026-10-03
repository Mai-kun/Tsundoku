namespace MediaTracker.Server.Features.Volumes.UpdateVolumeProgress;

public sealed record UpdateVolumeProgressRequest
{
    public int? CurrentPage { get; init; }

    public int? CurrentChapter { get; init; }
}
