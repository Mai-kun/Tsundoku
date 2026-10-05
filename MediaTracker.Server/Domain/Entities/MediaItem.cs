using MediaTracker.Server.Domain.Enums;

namespace MediaTracker.Server.Domain.Entities;

public abstract class MediaItem
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public required string Title { get; set; }

    public MediaStatus Status { get; internal set; } = MediaStatus.Planned;

    public int? Score { get; set; }

    public DateTime? StartedAt { get; set; }

    public DateTime? FinishedAt { get; set; }

    public string? Notes { get; set; }

    public string? CoverUrl { get; set; }

    /// <summary>Set to <see cref="SyncStatus.Syncing"/> the moment the row is created, so the card
    /// and the detail screen can render immediately while the job queue fills in the rest.</summary>
    public SyncStatus SyncStatus { get; set; } = SyncStatus.Ready;

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

    /// <summary>
    /// The related titles the user loaded from an external API, serialised once. Without this the
    /// Related tab was empty after every F5 and the user had to name a source again to get the list
    /// back; the payload is per-item and only the detail screen reads it.
    /// </summary>
    public string? RelatedMediaJson { get; set; }

    /// <summary>Which source produced <see cref="RelatedMediaJson"/>; null while nothing is cached.</summary>
    public string? RelatedSource { get; set; }

    /// <summary>
    /// The achievement list the provider reported, serialised once. Re-reading RAWG on every open was
    /// both slow and pointless: achievements only change when the game itself is patched, and the
    /// panel had to re-render 1000+ nodes each time. Same trade-off as
    /// <see cref="RelatedMediaJson"/>.
    /// </summary>
    public string? AchievementsJson { get; set; }

    /// <summary>Recommendations the user loaded, cached for the same reason as the achievements.</summary>
    public string? RecommendationsJson { get; set; }

    /// <summary>When <see cref="RecommendationsJson"/> was last written; drives the cache window.</summary>
    public DateTime? RecommendationsUpdatedAt { get; set; }

    /// <summary>
    /// How long a fetched recommendation list stays authoritative. The provider is not called again
    /// inside this window, so re-opening the tab — or reloading the page — costs no network at all.
    /// </summary>
    public static readonly TimeSpan RecommendationLifetime = TimeSpan.FromDays(30);

    /// <summary>
    /// Whether the stored list can be replayed without asking the provider again. Both halves matter:
    /// a payload without a timestamp was written before this rule existed and must be refetched.
    /// </summary>
    public bool HasFreshRecommendations(DateTime now) =>
        RecommendationsJson is not null
        && RecommendationsUpdatedAt is { } writtenAt
        && now - writtenAt < RecommendationLifetime;

    public void CacheRecommendations(string json, DateTime now)
    {
        RecommendationsJson = json;
        RecommendationsUpdatedAt = now;
    }

    /// <summary>
    /// The user typed into this row themselves, so a refresh must not silently throw it away. Set by
    /// the updater the moment a manual edit actually changes a stored value, and only cleared by an
    /// explicit full overwrite — which is exactly what the safe-merge choice in the refresh dialog
    /// preserves it for.
    /// </summary>
    public bool IsCustomEdited { get; set; }

    /// <summary>
    /// Moves the item to <paramref name="status"/> and brings every dependent field along with it:
    /// timestamps, the type-specific counters and, for a show, its seasons. The status setter is
    /// private so a caller cannot change the status without these rules running.
    /// </summary>
    public void ChangeStatus(MediaStatus status, DateTime? now = null)
    {
        var stamp = now ?? DateTime.UtcNow;
        Status = status;

        switch (status)
        {
            case MediaStatus.Completed:
                FinishedAt ??= stamp;
                MarkProgressAsFinished();
                break;
            case MediaStatus.InProgress:
                StartedAt ??= stamp;
                FinishedAt = null;
                break;
            case MediaStatus.Planned:
                StartedAt = null;
                FinishedAt = null;
                ClearProgress();
                break;
            case MediaStatus.OnHold:
                FinishedAt = null;
                break;
            case MediaStatus.Dropped:
                FinishedAt ??= stamp;
                break;
        }
    }

    /// <summary>
    /// Sets the status without touching timestamps or counters. Only for the cases where the caller
    /// already owns those fields, such as an explicit field-by-field update.
    /// </summary>
    public void SetStatus(MediaStatus status) => Status = status;

    /// <summary>Applies a rolled-up progress verdict without re-running the full status transition.</summary>
    public void ApplyProgressStatus(MediaStatus status, DateTime? startedAt, DateTime? finishedAt)
    {
        Status = status;
        StartedAt = startedAt;
        FinishedAt = finishedAt;
    }

    /// <summary>Stamps the row as changed so the cover cache-buster moves with the payload.</summary>
    public void MarkUpdated(DateTime? now = null) => UpdatedAt = now ?? DateTime.UtcNow;

    /// <summary>
    /// Stores the release date and keeps the raw year alongside it. A source that only knows the year
    /// leaves the date unset so the UI never renders a fabricated 1 January.
    /// </summary>
    public void SetReleaseDate(DateTime? releaseDate, int? releaseYear)
    {
        ReleaseDate = releaseDate;

        if (releaseYear is > 0)
        {
            ReleaseYear = releaseYear;
        }
        else if (releaseDate is { } derived)
        {
            ReleaseYear = derived.Year;
        }
    }

    public void RecordExternalRating(double rating, int? votes, string? ratingsJson)
    {
        ExternalRating = rating;
        ExternalRatingVotes = votes;
        ExternalRatingsJson = ratingsJson;
    }

    /// <summary>
    /// "Planned" means nothing has been started yet, so a title moved back to it must not keep the
    /// counters it accumulated — otherwise a planned anime reads as 220/220 and every progress bar
    /// (card, banner, spec sheet) is full while the status says otherwise.
    /// </summary>
    protected virtual void ClearProgress()
    {
    }

    protected virtual void MarkProgressAsFinished()
    {
    }
}
