namespace MediaTracker.Server.Models;

public class TvSeason
{
    public Guid Id { get; set; }

    public int SeasonNumber { get; set; }

    public required string Title { get; set; }

    public string? CoverUrl { get; set; }

    public int CurrentEpisode { get; set; }

    public int TotalEpisodes { get; set; }

    public MediaStatus Status { get; set; }

    public int? Score { get; set; }

    public string? Notes { get; set; }

    public DateTime? AirDate { get; set; }

    public Guid TvShowId { get; set; }

    public TvShow TvShow { get; set; } = null!;
}
