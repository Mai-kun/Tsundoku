namespace MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;

public sealed record UpdateSeasonProgressRequest
{
    public required int CurrentEpisode { get; init; }
}
