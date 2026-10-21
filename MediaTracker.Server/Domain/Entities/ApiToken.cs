namespace MediaTracker.Server.Domain.Entities;

public class ApiToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public required string Name { get; set; } // e.g. "Home Assistant", max 100
    public required string TokenHash { get; set; } // SHA-256 hash
    public required string TokenPrefix { get; set; } // e.g. "tsk_live_ab12cd34"
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastUsedAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
}
