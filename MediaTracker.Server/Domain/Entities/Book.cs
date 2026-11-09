namespace MediaTracker.Server.Domain.Entities;

public class Book : MediaItem
{
    public required string Author { get; set; }

    public string? Publisher { get; set; }

    public string? Isbn { get; set; }

    /// <summary>book / light_novel / web_novel</summary>
    public string? Format { get; set; }

    public int CurrentPage { get; set; }

    public int TotalPages { get; set; }

    public int? CurrentChapter { get; set; }

    public int? TotalChapters { get; set; }

    public int? CurrentVolume { get; set; }

    public int? TotalVolumes { get; set; }

    /// <summary>Clamps to the known page count; an unknown total (0) leaves the request untouched.</summary>
    public void SetProgress(int currentPage, int totalPages)
    {
        TotalPages = Math.Max(totalPages, 0);
        CurrentPage = totalPages > 0
            ? Math.Min(Math.Max(currentPage, 0), totalPages)
            : Math.Max(currentPage, 0);
    }

    public void SetChapter(int chapter)
    {
        CurrentChapter = TotalChapters is > 0
            ? Math.Min(Math.Max(chapter, 0), TotalChapters.Value)
            : Math.Max(chapter, 0);
    }

    protected override void ClearProgress()
    {
        CurrentPage = 0;
        CurrentChapter = 0;
        CurrentVolume = 0;
    }

    protected override void MarkProgressAsFinished()
    {
        if (TotalPages > 0)
        {
            CurrentPage = TotalPages;
        }
        if (TotalChapters is > 0)
        {
            CurrentChapter = TotalChapters.Value;
        }
    }
}
