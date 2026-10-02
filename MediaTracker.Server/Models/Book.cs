namespace MediaTracker.Server.Models;

public class Book : MediaItem
{
    public required string Author { get; set; }

    public int CurrentPage { get; set; }

    public int TotalPages { get; set; }
}
