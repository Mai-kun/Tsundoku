namespace MediaTracker.Server.DTOs;

public sealed record UpdateSeasonProgressRequest
{
    public required int CurrentEpisode { get; init; }
}