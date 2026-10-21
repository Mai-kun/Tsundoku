namespace MediaTracker.Server.Domain.Entities;

public class Book : MediaItem
{
    public required string Author { get; set; }

    public int CurrentPage { get; set; }

    public int TotalPages { get; set; }

    /// <summary>Clamps to the known page count; an unknown total (0) leaves the request untouched.</summary>
    public void SetProgress(int currentPage, int totalPages)
    {
        TotalPages = Math.Max(totalPages, 0);
        CurrentPage = totalPages > 0
            ? Math.Min(Math.Max(currentPage, 0), totalPages)
            : Math.Max(currentPage, 0);
    }

    protected override void ClearProgress() => CurrentPage = 0;

    protected override void MarkProgressAsFinished()
    {
        if (TotalPages > 0)
        {
            CurrentPage = TotalPages;
        }
    }
}
