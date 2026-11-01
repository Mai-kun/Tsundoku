namespace MediaTracker.Server.Domain.Entities;

/// <summary>
/// A gamified yearly or thematic goal ("read 12 books in 2026", "retro marathon: 5 pre-2000
/// movies"). Progress is never stored: <see cref="Features.Goals.GoalsHandler"/> computes it live
/// from the completed media matching the category filter and the optional smart query, so the
/// number always reflects the library as it is right now.
/// </summary>
public sealed class Goal
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Title { get; set; } = string.Empty;

    public string? Description { get; set; }

    /// <summary>Emoji or icon key shown on the goal card.</summary>
    public string? Icon { get; set; } = "🎯";

    /// <summary>The calendar year this goal counts completed titles in (e.g. 2026).</summary>
    public int Year { get; set; }

    /// <summary>How many completed titles close the goal.</summary>
    public int TargetCount { get; set; }

    /// <summary>"all" | "book" | "movie" | "anime" | "manga" | "game" | "tvshow".</summary>
    public string? Category { get; set; }

    /// <summary>Optional extra filtering rules (<see cref="Features.Lists.SmartListQueryDto"/> JSON).</summary>
    public string? SmartQueryJson { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
