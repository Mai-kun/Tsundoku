using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

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
public sealed class DeleteHistoryEventHandler(AppDbContext db) : IDeleteHistoryEventHandler
{
    public async Task<Result> HandleAsync(DeleteHistoryEventCommand command, CancellationToken ct)
    {
        var entry = await db.Events.FindAsync([command.EventId], ct);

        if (entry is null)
        {
            return Result.Failure(Error.NotFound($"History entry '{command.EventId}' was not found."));
        }

        db.Events.Remove(entry);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
