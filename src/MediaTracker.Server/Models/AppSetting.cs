namespace MediaTracker.Server.Models;

public class AppSetting
{
    public required string Key { get; set; }

    public required string Value { get; set; }

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
