namespace MediaTracker.Server.DTOs;

public sealed record MediaStatsDto
{
    public int TotalItems { get; init; }

    public int CompletedItems { get; init; }

    public int InProgressItems { get; init; }

    public int PlannedItems { get; init; }

    public int TotalHoursPlayed { get; init; }

    public int TotalPagesRead { get; init; }

    public int TotalChaptersRead { get; init; }

    public int TotalEpisodesWatched { get; init; }

    public int CompletedGamesCount { get; init; }

    public int CompletedBooksCount { get; init; }

    public int CompletedMoviesCount { get; init; }
}
