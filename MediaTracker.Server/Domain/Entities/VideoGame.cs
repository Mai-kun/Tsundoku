namespace MediaTracker.Server.Domain.Entities;

public class VideoGame : MediaItem
{
    public required string Platform { get; set; }

    public int? HoursPlayed { get; set; }

    /// <summary>Developer (Steam calls them developers; RAWG reports the same list). Null when no
    /// source has ever told us who made the game. Drives the overview's "Разработчик" card.</summary>
    public string? Studio { get; set; }

    public void SetHoursPlayed(int hours) => HoursPlayed = Math.Max(hours, 0);

    protected override void ClearProgress() => HoursPlayed = 0;
}
