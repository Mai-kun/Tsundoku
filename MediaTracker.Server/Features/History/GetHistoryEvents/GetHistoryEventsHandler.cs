using Dapper;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;

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
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        var sb = new global::System.Text.StringBuilder("""
            SELECT e.Id, e.MediaId, e.Type, e.OldValue, e.NewValue, e.CreatedAt, m.Title
            FROM Events e
            LEFT JOIN MediaItems m ON e.MediaId = m.Id
            WHERE 1=1
            """);
        var paramIndex = 0;

        if (query.MediaId is { } mediaId)
        {
            sb.Append(" AND e.MediaId = @p").Append(paramIndex);
            cmd.Parameters.Add(new Microsoft.Data.Sqlite.SqliteParameter($"@p{paramIndex}", mediaId.ToString().ToUpperInvariant()));
            paramIndex++;
        }

        if (query.Date is { } date)
        {
            var start = date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
            var end = date.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);
            sb.Append(" AND e.CreatedAt >= @p").Append(paramIndex);
            cmd.Parameters.Add(new Microsoft.Data.Sqlite.SqliteParameter($"@p{paramIndex}", start.ToString("o")));
            paramIndex++;
            sb.Append(" AND e.CreatedAt <= @p").Append(paramIndex);
            cmd.Parameters.Add(new Microsoft.Data.Sqlite.SqliteParameter($"@p{paramIndex}", end.ToString("o")));
            paramIndex++;
        }

        sb.Append(" ORDER BY e.CreatedAt DESC LIMIT @p").Append(paramIndex);
        cmd.Parameters.Add(new Microsoft.Data.Sqlite.SqliteParameter($"@p{paramIndex}", MaxEvents));
        cmd.CommandText = sb.ToString();

        using var reader = await cmd.ExecuteReaderAsync(ct);
        var events = new List<HistoryEventDto>();
        while (await reader.ReadAsync(ct))
        {
            events.Add(new HistoryEventDto(
                Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                Guid.Parse(reader.GetString(reader.GetOrdinal("MediaId"))),
                ((MediaEventType)reader.GetInt32(reader.GetOrdinal("Type"))).ToString(),
                reader.IsDBNull(reader.GetOrdinal("OldValue")) ? null : reader.GetString(reader.GetOrdinal("OldValue")),
                reader.IsDBNull(reader.GetOrdinal("NewValue")) ? null : reader.GetString(reader.GetOrdinal("NewValue")),
                reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                reader.IsDBNull(reader.GetOrdinal("Title")) ? null : reader.GetString(reader.GetOrdinal("Title"))));
        }

        return Result<IReadOnlyList<HistoryEventDto>>.Success(events);
    }
}
