namespace MediaTracker.Server.Features.Media.GetMediaStats;

public record AdvancedStatsDto
{
    public int TotalTitles { get; init; }
    public int CompletedTitles { get; init; }
    public double CompletionRatePercent { get; init; }
    public double TotalHours { get; init; }
    public double TotalDays { get; init; }

    public double GameHours { get; init; }
    public double MovieHours { get; init; }
    public double SeriesHours { get; init; }
    public double AnimeHours { get; init; }
    public double BookHours { get; init; }
    public double MangaHours { get; init; }

    public int TotalPagesRead { get; init; }
    public int TotalChaptersRead { get; init; }
    public int TotalEpisodesWatched { get; init; }

    public double AverageScore { get; init; }
    public Dictionary<int, int> ScoreDistribution { get; init; } = new();
    public Dictionary<string, double> AverageScoreByType { get; init; } = new();

    public int CurrentStreakDays { get; init; }
    public List<MonthlyActivityDto> MonthlyCompletions { get; init; } = [];
    public List<GenreStatDto> TopGenres { get; init; } = [];
}

public record MonthlyActivityDto(string MonthYear, int Count);
public record GenreStatDto(string Genre, int Count, double Percentage);
