namespace MediaTracker.Server.Domain.Entities;

public class TvShow : MediaItem
{
    public string? Network { get; set; }

    public bool IsAnime { get; set; }

    public string? Studio { get; set; }

    public string? RomajiTitle { get; set; }

    public int? EpisodeDurationMinutes { get; set; }

    public List<TvSeason> Seasons { get; set; } = [];

    public int TotalEpisodesWatched => Seasons.Sum(season => season.CurrentEpisode);

    public int TotalEpisodesCount => Seasons.Sum(season => season.TotalEpisodes);

    public bool AllSeasonsCompleted => Seasons.Count > 0 && Seasons.All(season => season.IsCompleted);

    /// <summary>
    /// Rolls the season totals up onto the show: every season finished completes the show, any watched
    /// episode moves it to in progress, and dropping back to zero returns it to planned. Mirrors the
    /// per-season rules so a show never keeps a "completed" badge with un-watched seasons.
    /// </summary>
    public void SyncStatusFromSeasons(DateTime? now = null)
    {
        var stamp = now ?? DateTime.UtcNow;

        if (AllSeasonsCompleted)
        {
            ApplyProgressStatus(MediaStatus.Completed, StartedAt ?? stamp, FinishedAt ?? stamp);
            return;
        }

        if (TotalEpisodesWatched > 0)
        {
            var status = Status is MediaStatus.Completed or MediaStatus.Planned
                ? MediaStatus.InProgress
                : Status;

            ApplyProgressStatus(status, StartedAt ?? stamp, null);
            return;
        }

        var rewound = Status is MediaStatus.InProgress or MediaStatus.Completed
            ? MediaStatus.Planned
            : Status;

        ApplyProgressStatus(rewound, null, null);
    }

    protected override void ClearProgress()
    {
        foreach (var season in Seasons)
        {
            season.ResetProgress();
        }
    }

    protected override void MarkProgressAsFinished()
    {
        foreach (var season in Seasons)
        {
            season.MarkCompleted();
        }
    }
}
