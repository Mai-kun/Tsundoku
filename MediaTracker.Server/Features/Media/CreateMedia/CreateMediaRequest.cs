using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Volumes.AddVolume;

namespace MediaTracker.Server.Features.Media.CreateMedia;

public sealed record CreateMediaRequest
{
    public required string Type { get; init; }

    public required string Title { get; init; }

    public MediaStatus Status { get; init; } = MediaStatus.Planned;

    public int? Score { get; init; }

    public string? CoverUrl { get; init; }

    public string? Notes { get; init; }

    public Guid? FranchiseId { get; init; }

    public string? FranchiseName { get; init; }

    public int? FranchiseOrder { get; init; }

    public string? Platform { get; init; }

    public int? HoursPlayed { get; init; }

    public string? Author { get; init; }

    public int? TotalPages { get; init; }

    public int? TotalChapters { get; init; }

    public int? CurrentVolume { get; init; }

    public int? DurationMinutes { get; init; }

    public int? EpisodeDurationMinutes { get; init; }

    public DateTime? ReleaseDate { get; init; }

    public int? ReleaseYear { get; init; }

    public string? WatchedOn { get; init; }

    public DateTime? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    public string? Director { get; init; }

    public bool? IsAnime { get; init; }

    public string? Studio { get; init; }
    public string? RomajiTitle { get; init; }

    public string? Network { get; init; }

    public List<CreateSeasonRequest>? Seasons { get; init; }

    public int? TotalVolumes { get; init; }

    public List<CreateVolumeRequest>? Volumes { get; init; }

    public string? ExternalId { get; init; }

    public string? ExternalSource { get; init; }

    public double? ExternalRating { get; init; }

    public int? ExternalRatingVotes { get; init; }

    public string? ExternalRatingsJson { get; init; }

    public string? Genres { get; init; }

    public string? Tags { get; init; }

    public string? UnlockedAchievements { get; init; }

    public string? UserPlatform { get; init; }
}
