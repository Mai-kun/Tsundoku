namespace MediaTracker.Server.Models;

public abstract class MediaItem
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public required string Title { get; set; }

    public MediaStatus Status { get; set; } = MediaStatus.Planned;

    public int? Score { get; set; }

    public DateTime? StartedAt { get; set; }

    public DateTime? FinishedAt { get; set; }

    public string? Notes { get; set; }

    public string? CoverUrl { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Guid? FranchiseId { get; set; }

    public Franchise? Franchise { get; set; }

    public int? FranchiseOrder { get; set; }

    public string? ExternalId { get; set; }

    public string? ExternalSource { get; set; }

    public double? ExternalRating { get; set; }

    public int? ExternalRatingVotes { get; set; }

    public string? ExternalRatingsJson { get; set; }

    public DateTime? ReleaseDate { get; set; }

    /// <summary>Year kept separately: sources that only know the year must not fabricate Jan 1.</summary>
    public int? ReleaseYear { get; set; }

    public DateTime? EndDate { get; set; }

    /// <summary>Where the user consumed it (streaming service, cinema, ...). Free text or a known site.</summary>
    public string? WatchedOn { get; set; }

    public string? ReleaseStatus { get; set; }

    public string? TranslatedSynopsis { get; set; }

    public string? TranslationLanguage { get; set; }

    public string? Genres { get; set; }

    public string? Tags { get; set; }

    public string? UnlockedAchievements { get; set; }

    public string? UserPlatform { get; set; }
}
