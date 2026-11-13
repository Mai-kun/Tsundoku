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

    public int SeasonsCount => Seasons.Count;

    public bool AllSeasonsCompleted => Seasons.Count > 0 && Seasons.All(season => season.IsCompleted);

    /// <summary>
    /// Rule 2's counter reset for a show: the seasons roll down with it, so a title that left
    /// "Completed" never keeps watched seasons behind the zeroed banner. No other status change
    /// touches the seasons.
    /// </summary>
    public override void ResetProgress()
    {
        foreach (var season in Seasons)
        {
            season.ResetProgress();
        }
    }
}
