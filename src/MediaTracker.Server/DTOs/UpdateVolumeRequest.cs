using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public sealed record UpdateVolumeRequest
{
    public string? Title { get; init; }

    public string? CoverUrl { get; init; }

    public int? TotalPages { get; init; }

    public int? CurrentPage { get; init; }

    public int? TotalChapters { get; init; }

    public int? CurrentChapter { get; init; }

    public MediaStatus? Status { get; init; }

    public int? Score { get; init; }

    public string? Notes { get; init; }
}
