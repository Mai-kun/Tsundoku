namespace MediaTracker.Server.Models;

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
}
