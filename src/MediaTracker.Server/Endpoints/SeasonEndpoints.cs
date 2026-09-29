using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Endpoints;

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

        var season = await db.TvSeasons.SingleOrDefaultAsync(item => item.Id == id, ct);
        if (season is null)
        {
            return Results.NotFound();
        }

        season.CurrentEpisode = season.TotalEpisodes > 0
            ? Math.Min(Math.Max(request.CurrentEpisode, 0), season.TotalEpisodes)
            : Math.Max(request.CurrentEpisode, 0);

        if (season.TotalEpisodes > 0 && season.CurrentEpisode >= season.TotalEpisodes)
        {
            season.Status = MediaStatus.Completed;
        }
        else if (season.CurrentEpisode > 0)
        {
            season.Status = MediaStatus.InProgress;
        }
        else
        {
            season.Status = MediaStatus.Planned;
        }

        var show = await db.TvShows.Include(item => item.Seasons).SingleOrDefaultAsync(item => item.Id == season.TvShowId, ct);
        if (show?.Seasons.Count > 0)
        {
            var totalWatched = show.Seasons.Sum(item => item.CurrentEpisode);
            var allCompleted = show.Seasons.All(item => item.Status == MediaStatus.Completed);

            if (allCompleted)
            {
                show.Status = MediaStatus.Completed;
                show.FinishedAt ??= DateTime.UtcNow;
                show.StartedAt ??= DateTime.UtcNow;
            }
            else if (totalWatched > 0)
            {
                if (show.Status is MediaStatus.Completed or MediaStatus.Planned)
                {
                    show.Status = MediaStatus.InProgress;
                }
                show.FinishedAt = null;
                show.StartedAt ??= DateTime.UtcNow;
            }
            else
            {
                show.StartedAt = null;
                show.FinishedAt = null;
                if (show.Status is MediaStatus.InProgress or MediaStatus.Completed)
                {
                    show.Status = MediaStatus.Planned;
                }
            }
        }

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
