using Dapper;
using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Domain.Rules;
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

        // Stepper hot path: read only the scalars the decision needs, then UPDATE directly.
        var idStr = command.SeasonId.ToString().ToUpperInvariant();
        var season = await db.Connection.QueryFirstOrDefaultAsync<TvSeasonRow>(
            "SELECT Id, TotalEpisodes, TvShowId, CurrentEpisode, Status, SeasonNumber FROM TvSeasons WHERE Id = @id",
            new { id = idStr });

        if (season is null)
        {
            return Result.Failure(Error.NotFound($"Season '{command.SeasonId}' was not found."));
        }

        var currentEpisode = TvSeason.Clamp(command.CurrentEpisode, season.TotalEpisodes);
        // Rule 1 for the season: only the exact 0 → 1 step flips the season to InProgress; every
        // other episode change keeps the stored season status (no auto-complete on the finale,
        // no auto-planned on a rewind).
        var promoteSeason = ProgressStepperRules.PromotesToInProgress(season.CurrentEpisode, currentEpisode);
        var seasonStatus = promoteSeason ? MediaStatus.InProgress : season.Status;

        await db.Connection.ExecuteAsync(
            "UPDATE TvSeasons SET CurrentEpisode = @ep, Status = @status WHERE Id = @id",
            new { ep = currentEpisode, status = (int)seasonStatus, id = idStr });

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
                COUNT(*) as SeasonCount
            FROM TvSeasons WHERE TvShowId = @showId
            """,
            new { showId = season.TvShowId });

        if (totals is { SeasonCount: > 0 })
        {
            // Rule 1 for the show: only the exact 0 → 1 move of the aggregated watched total
            // promotes the show to InProgress; no auto-complete, no rewind to Planned.
            var newTotal = totals.TotalWatched ?? 0;
            var oldTotal = newTotal - (currentEpisode - season.CurrentEpisode);
            await TouchShowAsync(db, season.TvShowId, ProgressStepperRules.PromotesToInProgress(oldTotal, newTotal), ct);
        }
        else
        {
            await db.Connection.ExecuteAsync(
                "UPDATE MediaItems SET LastActivityAt = @now WHERE Id = @id",
                new { now = DateTime.UtcNow, id = season.TvShowId });
        }

        // The list projection carries TotalEpisodesWatched computed from the seasons, so the
        // cached DTO list is stale the moment a season row changes. Without this the post-commit
        // refetch hands the client the pre-step number and the card's optimistic value rolls back.
        MediaListCache.Invalidate();
        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
        return Result.Success();
    }

    /// <summary>
    /// Applies rule 1 to the parent show: a 0 → 1 move of the aggregated watched total promotes it
    /// to InProgress. Every other season change only refreshes LastActivityAt — the show's status
    /// and timestamps stay exactly as the user set them.
    /// </summary>
    private static async Task TouchShowAsync(AppDbContext db, Guid tvShowId, bool totalMovedZeroToOne, CancellationToken ct)
    {
        var showIdStr = tvShowId.ToString().ToUpperInvariant();
        var show = await db.Connection.QueryFirstOrDefaultAsync<ShowStatusRow>(
            "SELECT Status, StartedAt, FinishedAt FROM MediaItems WHERE Id = @id AND MediaType = 'TvShow'",
            new { id = showIdStr });

        if (show is null) return;

        if (totalMovedZeroToOne && show.Status != MediaStatus.InProgress)
        {
            var now = DateTime.UtcNow;
            await db.Connection.ExecuteAsync(
                """
                UPDATE MediaItems SET Status = @inProgress, StartedAt = COALESCE(StartedAt, @now),
                    FinishedAt = NULL, LastActivityAt = @now WHERE Id = @id
                """,
                new { inProgress = (int)MediaStatus.InProgress, now, id = showIdStr });

            await db.InsertMediaEventAsync(new MediaEvent
            {
                MediaId = tvShowId,
                Type = MediaEventType.StatusChanged,
                OldValue = show.Status.ToString(),
                NewValue = MediaStatus.InProgress.ToString(),
                CreatedAt = now
            }, ct);
            return;
        }

        await db.Connection.ExecuteAsync(
            "UPDATE MediaItems SET LastActivityAt = @now WHERE Id = @id",
            new { now = DateTime.UtcNow, id = showIdStr });
    }
}

/// <summary>Flat read row for a TvSeason.</summary>
public sealed class TvSeasonRow
{
    public Guid Id { get; set; }
    public int TotalEpisodes { get; set; }
    public Guid TvShowId { get; set; }
    public int CurrentEpisode { get; set; }
    public MediaStatus Status { get; set; }
    public int SeasonNumber { get; set; }
}

/// <summary>Flat read row for show status aggregation.</summary>
public sealed class TvShowTotalsRow
{
    public int? TotalWatched { get; set; }
    public int SeasonCount { get; set; }
}

/// <summary>Flat read row for show status.</summary>
public sealed class ShowStatusRow
{
    public MediaStatus Status { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? FinishedAt { get; set; }
}
