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
