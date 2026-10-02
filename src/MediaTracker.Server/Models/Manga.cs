namespace MediaTracker.Server.Models;

public class Manga : MediaItem
{
    public int CurrentChapter { get; set; }

    public int? TotalChapters { get; set; }

    public string? Author { get; set; }

    public string? RomajiTitle { get; set; }

    /// <summary>manga / manhwa / manhua / oel, derived from the external source. Null when unknown.</summary>
    public string? Format { get; set; }

    public int CurrentVolume { get; set; }

    public int? TotalVolumes { get; set; }

    public List<MangaVolume> Volumes { get; set; } = [];
}
