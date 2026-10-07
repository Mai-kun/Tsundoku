namespace MediaTracker.Server.Domain.Entities;

public sealed class CustomListItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ListId { get; set; }
    public CustomList List { get; set; } = null!;
    public Guid MediaItemId { get; set; }
    public MediaItem MediaItem { get; set; } = null!;
    public int Order { get; set; }
    public DateTime AddedAt { get; set; } = DateTime.UtcNow;
}
