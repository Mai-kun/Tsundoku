using Dapper;
using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;

public sealed record UpdateSeasonProgressCommand(Guid SeasonId, int CurrentEpisode);

public interface IUpdateSeasonProgressHandler
{
    Task<Result> HandleAsync(UpdateSeasonProgressCommand command, CancellationToken ct);
}

public sealed class UpdateSeasonProgressHandler(
    AppDbContext db,
    IValidator<UpdateSeasonProgressRequest> validator,
    IMemoryCache cache) : IUpdateSeasonProgressHandler
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
        var idStr = command.SeasonId.ToString().ToUpperInvariant();
        var season = await db.Connection.QueryFirstOrDefaultAsync<TvSeasonRow>(
            "SELECT Id, TotalEpisodes, TvShowId, CurrentEpisode, SeasonNumber FROM TvSeasons WHERE Id = @id",
            new { id = idStr });

        if (season is null)
        {
            return Result.Failure(Error.NotFound($"Season '{command.SeasonId}' was not found."));
        }

        var currentEpisode = TvSeason.Clamp(command.CurrentEpisode, season.TotalEpisodes);
        var newStatus = TvSeason.ResolveStatus(currentEpisode, season.TotalEpisodes);

        await db.Connection.ExecuteAsync(
            "UPDATE TvSeasons SET CurrentEpisode = @ep, Status = @status WHERE Id = @id",
            new { ep = currentEpisode, status = (int)newStatus, id = idStr });

        if (season.CurrentEpisode != currentEpisode)
        {
            await db.InsertMediaEventAsync(new MediaEvent
            {
                MediaId = season.TvShowId,
                Type = MediaEventType.ProgressChanged,
                OldValue = $"S{season.SeasonNumber} E{season.CurrentEpisode}",
                NewValue = $"S{season.SeasonNumber} E{currentEpisode}",
                CreatedAt = DateTime.UtcNow
            }, ct);
        }

        // Aggregate season totals for the parent show.
        var totals = await db.Connection.QueryFirstOrDefaultAsync<TvShowTotalsRow>(
            """
            SELECT 
                SUM(CurrentEpisode) as TotalWatched,
                COUNT(*) as SeasonCount,
                CASE WHEN MIN(CASE WHEN Status = 2 THEN 0 ELSE 1 END) = 0 THEN 1 ELSE 0 END as AllCompleted
            FROM TvSeasons WHERE TvShowId = @showId
            """,
            new { showId = season.TvShowId });

        if (totals is { SeasonCount: > 0 })
        {
            await SyncShowAsync(db, season.TvShowId, totals.AllCompleted == 1, totals.TotalWatched > 0, ct);
        }
        else
        {
            await db.Connection.ExecuteAsync(
                "UPDATE MediaItems SET LastActivityAt = @now WHERE Id = @id",
                new { now = DateTime.UtcNow, id = season.TvShowId });
        }

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
        return Result.Success();
    }

    private static async Task SyncShowAsync(AppDbContext db, Guid tvShowId, bool allCompleted, bool anyWatched, CancellationToken ct)
    {
        var showIdStr = tvShowId.ToString().ToUpperInvariant();
        var show = await db.Connection.QueryFirstOrDefaultAsync<ShowStatusRow>(
            "SELECT Status, StartedAt, FinishedAt FROM MediaItems WHERE Id = @id AND MediaType = 'TvShow'",
            new { id = showIdStr });

        if (show is null) return;

        var (newShowStatus, startedAt, finishedAt) = Domain.Rules.ProgressStepperRules.ResolveShowStatus(
            show.Status,
            show.StartedAt,
            show.FinishedAt,
            allCompleted,
            anyWatched,
            DateTime.UtcNow);

        await db.Connection.ExecuteAsync(
            """
            UPDATE MediaItems SET Status = @status, StartedAt = @startedAt, FinishedAt = @finishedAt,
                LastActivityAt = @now WHERE Id = @id
            """,
            new { status = (int)newShowStatus, startedAt, finishedAt, now = DateTime.UtcNow, id = showIdStr });
    }
}

/// <summary>Flat read row for a TvSeason.</summary>
public sealed class TvSeasonRow
{
    public Guid Id { get; set; }
    public int TotalEpisodes { get; set; }
    public Guid TvShowId { get; set; }
    public int CurrentEpisode { get; set; }
    public int SeasonNumber { get; set; }
}

/// <summary>Flat read row for show status aggregation.</summary>
public sealed class TvShowTotalsRow
{
    public int? TotalWatched { get; set; }
    public int SeasonCount { get; set; }
    public int AllCompleted { get; set; }
}

/// <summary>Flat read row for show status.</summary>
public sealed class ShowStatusRow
{
    public MediaStatus Status { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? FinishedAt { get; set; }
}
