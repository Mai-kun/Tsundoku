namespace MediaTracker.Server.Domain.Entities;

public class VideoGame : MediaItem
{
    public required string Platform { get; set; }

    public int? HoursPlayed { get; set; }

    public void SetHoursPlayed(int hours) => HoursPlayed = Math.Max(hours, 0);

    protected override void ClearProgress() => HoursPlayed = 0;
}
