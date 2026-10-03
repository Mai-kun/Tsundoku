using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.History.ClearHistory;

public interface IClearHistoryHandler
{
    Task<Result> HandleAsync(CancellationToken ct);
}

/// <summary>
/// Wipes the activity log and the start/finish stamps it is derived from, so the history screen and
/// the "when did I start this" columns agree afterwards.
/// </summary>
public sealed class ClearHistoryHandler(AppDbContext db) : IClearHistoryHandler
{
    public async Task<Result> HandleAsync(CancellationToken ct)
    {
        await db.Events.ExecuteDeleteAsync(ct);
        await db.MediaItems.ExecuteUpdateAsync(s => s
            .SetProperty(m => m.StartedAt, (DateTime?)null)
            .SetProperty(m => m.FinishedAt, (DateTime?)null), ct);

        return Result.Success();
    }
}
