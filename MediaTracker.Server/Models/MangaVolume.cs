namespace MediaTracker.Server.Models;

public class MangaVolume
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public int VolumeNumber { get; set; }

    public required string Title { get; set; }

    public string? CoverUrl { get; set; }

    public int CurrentPage { get; set; }

    public int TotalPages { get; set; }

    public int CurrentChapter { get; set; }

    public int TotalChapters { get; set; }

    public MediaStatus Status { get; set; }

    public int? Score { get; set; }

    public string? Notes { get; set; }

    public DateTime? ReleaseDate { get; set; }

    public Guid MangaId { get; set; }

    public Manga Manga { get; set; } = null!;
}
