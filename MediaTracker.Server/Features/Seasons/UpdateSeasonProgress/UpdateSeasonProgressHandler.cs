using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;

public sealed record UpdateSeasonProgressCommand(Guid SeasonId, int CurrentEpisode);

public interface IUpdateSeasonProgressHandler
{
    Task<Result> HandleAsync(UpdateSeasonProgressCommand command, CancellationToken ct);
}

/// <summary>
/// The season stepper. The season write is a single UPDATE with no tracked entity, and the parent
/// show's status is then recalculated from the season totals by <see cref="TvShow.SyncStatusFromSeasons"/>.
/// </summary>
public sealed class UpdateSeasonProgressHandler(
    AppDbContext db,
    IValidator<UpdateSeasonProgressRequest> validator) : IUpdateSeasonProgressHandler
{
    public async Task<Result> HandleAsync(UpdateSeasonProgressCommand command, CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(
            new UpdateSeasonProgressRequest { CurrentEpisode = command.CurrentEpisode },
            ct);

        if (validation.ToError() is { } validationError)
        {
            return Result.Failure(validationError);
        }

        // Stepper hot path: read only the two scalars the decision needs, then UPDATE directly.
        // No season entity is tracked and no parent show is pulled in with all of its seasons.
        var season = await db.TvSeasons
            .AsNoTracking()
            .Where(item => item.Id == command.SeasonId)
            .Select(item => new { item.TotalEpisodes, item.TvShowId })
            .FirstOrDefaultAsync(ct);

        if (season is null)
        {
            return Result.Failure(Error.NotFound($"Season '{command.SeasonId}' was not found."));
        }

        var currentEpisode = TvSeason.Clamp(command.CurrentEpisode, season.TotalEpisodes);
        var newStatus = TvSeason.ResolveStatus(currentEpisode, season.TotalEpisodes);

        await db.TvSeasons
            .Where(item => item.Id == command.SeasonId)
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
            await SyncShowAsync(season.TvShowId, totals.AllCompleted, totals.TotalWatched > 0, ct);
        }

        return Result.Success();
    }

    private async Task SyncShowAsync(Guid tvShowId, bool allCompleted, bool anyWatched, CancellationToken ct)
    {
        var show = await db.TvShows
            .AsNoTracking()
            .Where(item => item.Id == tvShowId)
            .Select(item => new { item.Status, item.StartedAt, item.FinishedAt })
            .FirstOrDefaultAsync(ct);

        if (show is null)
        {
            return;
        }

        var (newShowStatus, startedAt, finishedAt) = Domain.Rules.ProgressStepperRules.ResolveShowStatus(
            show.Status,
            show.StartedAt,
            show.FinishedAt,
            allCompleted,
            anyWatched,
            DateTime.UtcNow);

        await db.TvShows
            .Where(item => item.Id == tvShowId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(item => item.Status, newShowStatus)
                .SetProperty(item => item.StartedAt, startedAt)
                .SetProperty(item => item.FinishedAt, finishedAt), ct);
    }
}
