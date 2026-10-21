using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.History.GetHistoryEvents;

public sealed record HistoryEventDto(
    Guid Id,
    Guid MediaId,
    string Type,
    string? OldValue,
    string? NewValue,
    DateTime CreatedAt,
    string? Title);

public sealed record GetHistoryEventsQuery(Guid? MediaId = null, DateOnly? Date = null);

public interface IGetHistoryEventsHandler
{
    Task<Result<IReadOnlyList<HistoryEventDto>>> HandleAsync(GetHistoryEventsQuery query, CancellationToken ct);
}

/// <summary>The activity log behind the history screen: newest first, title joined in.</summary>
public sealed class GetHistoryEventsHandler(AppDbContext db) : IGetHistoryEventsHandler
{
    private const int MaxEvents = 500;

    public async Task<Result<IReadOnlyList<HistoryEventDto>>> HandleAsync(GetHistoryEventsQuery query, CancellationToken ct)
    {
        var eventsQuery = db.Events.AsNoTracking();

        if (query.MediaId is { } mediaId)
        {
            eventsQuery = eventsQuery.Where(e => e.MediaId == mediaId);
        }

        if (query.Date is { } date)
        {
            var start = date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
            var end = date.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);
            eventsQuery = eventsQuery.Where(e => e.CreatedAt >= start && e.CreatedAt <= end);
        }

        var events = await eventsQuery
            .OrderByDescending(e => e.CreatedAt)
            .Take(MaxEvents)
            .Select(e => new HistoryEventDto(
                e.Id,
                e.MediaId,
                // Serialised by name so the client can key its label/icon maps directly;
                // as a raw int every lookup came back undefined.
                e.Type.ToString(),
                e.OldValue,
                e.NewValue,
                e.CreatedAt,
                e.Media != null ? e.Media.Title : null))
            .ToListAsync(ct);

        return Result<IReadOnlyList<HistoryEventDto>>.Success(events);
    }
}
