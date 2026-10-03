using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.UpdateMedia;

public sealed record UpdateMediaRequest
{
    public string? Title { get; init; }

    public int? Score { get; init; }

    public MediaStatus? Status { get; init; }

    public string? Notes { get; init; }

    public string? CoverUrl { get; init; }

    public DateTime? StartedAt { get; init; }

    public DateTime? FinishedAt { get; init; }

    public Guid? FranchiseId { get; init; }

    public string? FranchiseName { get; init; }

    public int? FranchiseOrder { get; init; }

    public string? Author { get; init; }

    public string? RomajiTitle { get; init; }

    public int? TotalVolumes { get; init; }

    public int? CurrentVolume { get; init; }

    public int? TotalChapters { get; init; }

    public int? CurrentChapter { get; init; }

    public int? TotalPages { get; init; }

    public int? CurrentPage { get; init; }

    public string? TranslatedSynopsis { get; init; }

    public string? TranslationLanguage { get; init; }

    public string? Genres { get; init; }

    public string? Tags { get; init; }

    public string? UnlockedAchievements { get; init; }

    public string? UserPlatform { get; init; }

    public string? Platform { get; init; }

    /// <summary>Where the user watched it. Free text or one of the known sites.</summary>
    public string? WatchedOn { get; init; }

    /// <summary>Explicit null clears the value: every other field treats null as "not supplied".</summary>
    public bool ClearWatchedOn { get; init; }

    /// <summary>Explicit null clears the value: every other field treats null as "not supplied".</summary>
    public bool ClearUserPlatform { get; init; }
}
