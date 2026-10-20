namespace MediaTracker.Server.Domain.Entities;

public sealed class CustomList
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Icon { get; set; } = "list";
    public string? Color { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public List<CustomListItem> Items { get; set; } = [];
    public string? SmartQueryJson { get; set; }
}
