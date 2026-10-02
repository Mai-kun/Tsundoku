namespace MediaTracker.Server.Models;

public class Franchise
{
    public Guid Id { get; set; }

    public required string Name { get; set; }

    public string? Description { get; set; }

    public string? CoverUrl { get; set; }

    public List<MediaItem> Items { get; set; } = new();
}
