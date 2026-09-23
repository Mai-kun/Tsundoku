using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public sealed record CreateSeasonRequest
{
    public int SeasonNumber { get; init; }

    public required string Title { get; init; }

    public string? CoverUrl { get; init; }

    public int TotalEpisodes { get; init; }

    public MediaStatus Status { get; init; } = MediaStatus.Planned;

    public int? Score { get; init; }

    public string? Notes { get; init; }

    public DateTime? AirDate { get; init; }
}