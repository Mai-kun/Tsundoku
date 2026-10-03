namespace MediaTracker.Server.Domain.Entities;

public class MangaVolume
{
    public const int PlaceholderPagesPerVolume = 200;

    public Guid Id { get; set; } = Guid.NewGuid();

    public int VolumeNumber { get; set; }

    public required string Title { get; set; }

    public string? CoverUrl { get; set; }

    public int CurrentPage { get; internal set; }

    public int TotalPages { get; internal set; }

    public int CurrentChapter { get; internal set; }

    public int TotalChapters { get; internal set; }

    public MediaStatus Status { get; internal set; }

    public int? Score { get; set; }

    public string? Notes { get; set; }

    public DateTime? ReleaseDate { get; set; }

    public Guid MangaId { get; set; }

    public Manga Manga { get; set; } = null!;

    public bool IsCompleted =>
        (TotalChapters > 0 && CurrentChapter >= TotalChapters) ||
        (TotalPages > 0 && CurrentPage >= TotalPages);

    /// <summary>Clamps both counters and derives the volume status in one place.</summary>
    public void SetProgress(int currentPage, int currentChapter)
    {
        CurrentPage = Clamp(currentPage, TotalPages);
        CurrentChapter = Clamp(currentChapter, TotalChapters);
        Status = ResolveStatus(CurrentPage, TotalPages, CurrentChapter, TotalChapters);
    }

    /// <summary>Applies optional counter edits, keeping the counters the caller did not mention.</summary>
    public void ApplyEdits(int? currentPage, int? totalPages, int? currentChapter, int? totalChapters)
    {
        if (totalPages.HasValue)
        {
            TotalPages = Math.Max(totalPages.Value, 0);
        }

        if (totalChapters.HasValue)
        {
            TotalChapters = Math.Max(totalChapters.Value, 0);
        }

        if (currentPage.HasValue)
        {
            CurrentPage = Math.Max(currentPage.Value, 0);
        }

        if (currentChapter.HasValue)
        {
            CurrentChapter = Math.Max(currentChapter.Value, 0);
        }

        Status = ResolveStatus(CurrentPage, TotalPages, CurrentChapter, TotalChapters);
    }

    public void ApplyCounters(int currentPage, int totalPages, int currentChapter, int totalChapters)
    {
        TotalPages = Math.Max(totalPages, 0);
        TotalChapters = Math.Max(totalChapters, 0);
        CurrentPage = Math.Max(currentPage, 0);
        CurrentChapter = Math.Max(currentChapter, 0);
        Status = ResolveStatus(CurrentPage, TotalPages, CurrentChapter, TotalChapters);
    }

    public void ApplyStatus(MediaStatus status) => Status = status;

    /// <summary>The series-level chapter count also fills a stub volume that never knew its own.</summary>
    public void InheritTotalChapters(int totalChapters)
    {
        TotalChapters = Math.Max(totalChapters, 0);
        Status = ResolveStatus(CurrentPage, TotalPages, CurrentChapter, TotalChapters);
    }

    public static int Clamp(int value, int total) =>
        total > 0 ? Math.Min(Math.Max(value, 0), total) : Math.Max(value, 0);

    public static MediaStatus ResolveStatus(int currentPage, int totalPages, int currentChapter, int totalChapters) =>
        (totalChapters > 0 && currentChapter >= totalChapters) ||
        (totalPages > 0 && currentPage >= totalPages)
            ? MediaStatus.Completed
            : currentPage > 0 || currentChapter > 0
                ? MediaStatus.InProgress
                : MediaStatus.Planned;

    /// <summary>The blank volume a new series starts with, before any provider reports real counts.</summary>
    public static MangaVolume CreatePlaceholderVolume(int volumeNumber) =>
        new()
        {
            VolumeNumber = volumeNumber,
            Title = $"Volume {volumeNumber}",
            TotalChapters = 0,
            TotalPages = PlaceholderPagesPerVolume,
        };

    public static MangaVolume CreateFrom(
        int volumeNumber,
        string title,
        string? coverUrl,
        int totalPages,
        int currentPage,
        int totalChapters,
        int currentChapter,
        MediaStatus status,
        int? score,
        string? notes,
        DateTime? releaseDate,
        Guid mangaId)
    {
        var volume = new MangaVolume
        {
            MangaId = mangaId,
            VolumeNumber = volumeNumber,
            Title = title,
            CoverUrl = coverUrl,
            TotalPages = Math.Max(totalPages, 0),
            TotalChapters = Math.Max(totalChapters, 0),
            CurrentPage = Math.Max(currentPage, 0),
            CurrentChapter = Math.Max(currentChapter, 0),
            Status = status,
            Score = score,
            Notes = notes,
            ReleaseDate = releaseDate,
        };

        return volume;
    }
}
