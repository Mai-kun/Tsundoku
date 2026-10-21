namespace MediaTracker.Server.Features.Media.GetMediaStats;

public sealed record TasteProfileDto
{
    public TastePersonaDto Persona { get; init; } = null!;
    public SunkCostDto SunkCost { get; init; } = null!;
    public CriticalDivergenceDto Divergence { get; init; } = null!;
    public List<GenreCompletionStatDto> GenreParadox { get; init; } = [];
    public List<EraAffinityStatDto> EraAffinity { get; init; } = [];
    public List<RadarAxisDto> GenreRadar { get; init; } = [];
    public DropAnalyticsDto DropAnalytics { get; init; } = null!;
}

public sealed record DropAnalyticsDto(
    int TotalDropped,
    double AverageDropProgressPercent, // средний процент прогресса в момент дропа
    int EarlyDropCount,  // < 20% прогресса ("Правило первых серий/глав")
    int MidDropCount,    // 20% - 70% ("Затянутая середина")
    int LateDropCount,   // > 70% ("В шаге от финала")
    List<DropReasonStatDto> TopReasons
);
public sealed record DropReasonStatDto(string Reason, int Count, double Percentage);

public sealed record TastePersonaDto(string Title, string Description, string Icon, List<string> Traits);
public sealed record SunkCostDto(double LowScoreHours, double PercentageOfTotal, int TitlesCount, Dictionary<string, double> CategoryBreakdown);
public sealed record CriticalDivergenceDto(DivergenceItemDto? HiddenGem, DivergenceItemDto? Disappointment);
public sealed record DivergenceItemDto(Guid Id, string Title, string Type, string? CoverUrl, double UserScore, double WorldRating, double Delta);
public sealed record GenreCompletionStatDto(string Genre, int Total, int Completed, int Dropped, double CompletionRate, double DropRate);
public sealed record EraAffinityStatDto(string Era, int Count, double Percentage);
public sealed record RadarAxisDto(string Genre, double VolumeScore, double AverageScore);
