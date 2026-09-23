namespace MediaTracker.Server.Models;

public class Manga : MediaItem
{
    public int CurrentChapter { get; set; }

    public int? TotalChapters { get; set; }

    public int CurrentVolume { get; set; }
}
