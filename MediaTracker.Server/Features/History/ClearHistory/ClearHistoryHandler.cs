using Dapper;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.History.ClearHistory;

public interface IClearHistoryHandler
{
    Task<Result> HandleAsync(CancellationToken ct);
}

/// <summary>
/// Wipes the activity log and the start/finish stamps it is derived from, so the history screen and
/// the "when did I start this" columns agree afterwards.
/// </summary>
public sealed class ClearHistoryHandler(AppDbContext db, IMemoryCache cache) : IClearHistoryHandler
{
    public async Task<Result> HandleAsync(CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        await conn.ExecuteAsync("DELETE FROM Events;");
        await conn.ExecuteAsync("UPDATE MediaItems SET StartedAt = NULL, FinishedAt = NULL;");

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);

        return Result.Success();
    }
}
