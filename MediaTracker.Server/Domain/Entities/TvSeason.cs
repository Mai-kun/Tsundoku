namespace MediaTracker.Server.Domain.Entities;

public class TvSeason
{
    public Guid Id { get; set; }

    public int SeasonNumber { get; set; }

    public required string Title { get; set; }

    public string? CoverUrl { get; set; }

    public int CurrentEpisode { get; internal set; }

    public int TotalEpisodes { get; set; }

    public MediaStatus Status { get; internal set; }

    public int? Score { get; set; }

    public string? Notes { get; set; }

    public DateTime? AirDate { get; set; }

    public string? EpisodesData { get; set; }

    public Guid TvShowId { get; set; }

    public TvShow TvShow { get; set; } = null!;

    public bool IsCompleted => TotalEpisodes > 0 && CurrentEpisode >= TotalEpisodes;

    /// <summary>Clamps a requested episode to the season length; an unknown length floors at zero.</summary>
    public static int Clamp(int episode, int totalEpisodes) =>
        totalEpisodes > 0 ? Math.Min(Math.Max(episode, 0), totalEpisodes) : Math.Max(episode, 0);

    /// <summary>
    /// The stepper's write: clamps the episode to the season length and derives the season status, so
    /// reaching the finale completes the season without the caller deciding that.
    /// </summary>
    public void SetEpisode(int episode)
    {
        CurrentEpisode = TotalEpisodes > 0
            ? Math.Min(Math.Max(episode, 0), TotalEpisodes)
            : Math.Max(episode, 0);

        Status = ResolveStatus(CurrentEpisode, TotalEpisodes);
    }

    /// <summary>Creates the placeholder season a provider's episode list or count implies.</summary>
    public static TvSeason CreateFirst(int totalEpisodes, string? episodesData, MediaStatus status, Guid tvShowId) =>
        CreateSeason(1, "Season 1", totalEpisodes, episodesData, status, tvShowId);

    /// <summary>Creates a season for a specific season number, for sources that report the real split.</summary>
    public static TvSeason CreateSeason(
        int seasonNumber,
        string? title,
        int totalEpisodes,
        string? episodesData,
        MediaStatus status,
        Guid tvShowId) =>
        new()
        {
            Id = Guid.NewGuid(),
            SeasonNumber = seasonNumber,
            Title = string.IsNullOrWhiteSpace(title) ? $"Season {seasonNumber}" : title,
            TvShowId = tvShowId,
            Status = ResolveStatus(0, totalEpisodes),
            TotalEpisodes = totalEpisodes,
            EpisodesData = episodesData,
        };

    /// <summary>Backfills the counters of a season that already exists.</summary>
    public void ApplyEpisodeData(int totalEpisodes, string? episodesData)
    {
        TotalEpisodes = totalEpisodes;
        EpisodesData = episodesData;
    }

    public void MarkCompleted()
    {
        CurrentEpisode = TotalEpisodes;
        Status = MediaStatus.Completed;
    }

    public void ResetProgress()
    {
        CurrentEpisode = 0;
        Status = MediaStatus.Planned;
    }

    public void ApplyProgress(MediaStatus status, int currentEpisode)
    {
        Status = status;
        CurrentEpisode = currentEpisode;
    }

    public static MediaStatus ResolveStatus(int currentEpisode, int totalEpisodes) =>
        totalEpisodes > 0 && currentEpisode >= totalEpisodes ? MediaStatus.Completed
        : currentEpisode > 0 ? MediaStatus.InProgress
        : MediaStatus.Planned;
}
