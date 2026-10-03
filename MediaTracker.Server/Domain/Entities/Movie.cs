namespace MediaTracker.Server.Domain.Entities;

public class Movie : MediaItem
{
    public int DurationMinutes { get; set; }

    public string? Director { get; set; }

    public bool IsAnime { get; set; }

    public string? Studio { get; set; }

    public string? RomajiTitle { get; set; }
}
