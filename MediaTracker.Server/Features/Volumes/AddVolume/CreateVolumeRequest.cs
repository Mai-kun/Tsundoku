using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Volumes.AddVolume;

public sealed record CreateVolumeRequest
{
    public int VolumeNumber { get; init; }

    public required string Title { get; init; }

    public string? CoverUrl { get; init; }

    public int TotalPages { get; init; }

    public int CurrentPage { get; init; }

    public int TotalChapters { get; init; }

    public int CurrentChapter { get; init; }

    public MediaStatus Status { get; init; } = MediaStatus.Planned;

    public int? Score { get; init; }

    public string? Notes { get; init; }

    public DateTime? ReleaseDate { get; init; }
}
