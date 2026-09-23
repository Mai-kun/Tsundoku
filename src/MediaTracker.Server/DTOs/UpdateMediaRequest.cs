using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public sealed record UpdateMediaRequest
{
    public string? Title { get; init; }

    public int? Score { get; init; }

    public MediaStatus? Status { get; init; }

    public string? Notes { get; init; }

    public string? CoverUrl { get; init; }

    public DateTime? StartedAt { get; init; }

    public DateTime? FinishedAt { get; init; }
}