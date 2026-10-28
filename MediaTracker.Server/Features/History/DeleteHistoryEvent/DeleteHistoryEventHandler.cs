using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.History.DeleteHistoryEvent;

public sealed record DeleteHistoryEventCommand(Guid EventId);

public interface IDeleteHistoryEventHandler
{
    Task<Result> HandleAsync(DeleteHistoryEventCommand command, CancellationToken ct);
}

/// <summary>
/// Removes a single activity-log entry. The id is the event's own id (the list the UI renders), not
/// the media id, so deleting one row leaves the rest of that title's history intact.
/// </summary>
public sealed class DeleteHistoryEventHandler(AppDbContext db, IMemoryCache cache) : IDeleteHistoryEventHandler
{
    public async Task<Result> HandleAsync(DeleteHistoryEventCommand command, CancellationToken ct)
    {
        var rows = await db.DeleteMediaEventAsync(command.EventId, ct);
        if (rows == 0)
        {
            return Result.Failure(Error.NotFound($"History entry '{command.EventId}' was not found."));
        }

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
        return Result.Success();
    }
}
