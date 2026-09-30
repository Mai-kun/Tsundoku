using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Endpoints;

public static class ProgressStepperRules
{
    public static int Clamp(int value, int total) =>
        total > 0 ? Math.Min(Math.Max(value, 0), total) : Math.Max(value, 0);

    public static MediaStatus ResolveEpisodeStatus(int currentEpisode, int totalEpisodes) =>
        totalEpisodes > 0 && currentEpisode >= totalEpisodes ? MediaStatus.Completed
        : currentEpisode > 0 ? MediaStatus.InProgress
        : MediaStatus.Planned;

    public static MediaStatus ResolveVolumeStatus(int currentPage, int totalPages, int currentChapter, int totalChapters) =>
        (totalChapters > 0 && currentChapter >= totalChapters) ||
        (totalPages > 0 && currentPage >= totalPages)
            ? MediaStatus.Completed
            : currentPage > 0 || currentChapter > 0
                ? MediaStatus.InProgress
                : MediaStatus.Planned;

    /// <summary>
    /// Rolls the season totals up onto the parent show. Mirrors MediaStatusTransitions so a show
    /// never keeps a "completed" badge with un-watched seasons.
    /// </summary>
    public static (MediaStatus Status, DateTime? StartedAt, DateTime? FinishedAt) ResolveShowStatus(
        MediaStatus currentStatus,
        DateTime? currentStartedAt,
        DateTime? currentFinishedAt,
        bool allCompleted,
        bool anyWatched,
        DateTime now)
    {
        if (allCompleted)
        {
            return (MediaStatus.Completed, currentStartedAt ?? now, currentFinishedAt ?? now);
        }

        if (anyWatched)
        {
            return (
                currentStatus is MediaStatus.Completed or MediaStatus.Planned ? MediaStatus.InProgress : currentStatus,
                currentStartedAt ?? now,
                null);
        }

        return (
            currentStatus is MediaStatus.InProgress or MediaStatus.Completed ? MediaStatus.Planned : currentStatus,
            null,
            null);
    }
}

public static class SeasonEndpoints
{
    public static IEndpointRouteBuilder MapSeasonEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/seasons");

        group.MapPut("/{id:guid}/progress", UpdateSeasonProgress);

        return app;
    }

    private static async Task<IResult> UpdateSeasonProgress(
        Guid id,
        UpdateSeasonProgressRequest request,
        AppDbContext db,
        IValidator<UpdateSeasonProgressRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        // Stepper hot path: read only the two scalars the decision needs, then UPDATE directly.
        // No season entity is tracked and no parent show is pulled in with all of its seasons.
        var season = await db.TvSeasons
            .AsNoTracking()
            .Where(item => item.Id == id)
            .Select(item => new { item.TotalEpisodes, item.TvShowId })
            .FirstOrDefaultAsync(ct);

        if (season is null)
        {
            return Results.NotFound();
        }

        var currentEpisode = season.TotalEpisodes > 0
            ? Math.Min(Math.Max(request.CurrentEpisode, 0), season.TotalEpisodes)
            : Math.Max(request.CurrentEpisode, 0);

        var newStatus = ProgressStepperRules.ResolveEpisodeStatus(currentEpisode, season.TotalEpisodes);

        await db.TvSeasons
            .Where(item => item.Id == id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(item => item.CurrentEpisode, currentEpisode)
                .SetProperty(item => item.Status, newStatus), ct);

        var totals = await db.TvSeasons
            .AsNoTracking()
            .Where(item => item.TvShowId == season.TvShowId)
            .GroupBy(_ => 1)
            .Select(g => new
            {
                TotalWatched = g.Sum(item => item.CurrentEpisode),
                SeasonCount = g.Count(),
                AllCompleted = g.All(item => item.Status == MediaStatus.Completed)
            })
            .FirstOrDefaultAsync(ct);

        if (totals is { SeasonCount: > 0 })
        {
            var show = await db.TvShows
                .AsNoTracking()
                .Where(item => item.Id == season.TvShowId)
                .Select(item => new { item.Status, item.StartedAt, item.FinishedAt })
                .FirstOrDefaultAsync(ct);

            if (show is not null)
            {
                var now = DateTime.UtcNow;
                var (newShowStatus, startedAt, finishedAt) = ProgressStepperRules.ResolveShowStatus(
                    show.Status,
                    show.StartedAt,
                    show.FinishedAt,
                    totals.AllCompleted,
                    totals.TotalWatched > 0,
                    now);

                await db.TvShows
                    .Where(item => item.Id == season.TvShowId)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(item => item.Status, newShowStatus)
                        .SetProperty(item => item.StartedAt, startedAt)
                        .SetProperty(item => item.FinishedAt, finishedAt), ct);
            }
        }

        return Results.NoContent();
    }
}
