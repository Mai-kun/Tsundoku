namespace MediaTracker.Server.Models;

public class VideoGame : MediaItem
{
    public required string Platform { get; set; }

    public int? HoursPlayed { get; set; }
}
