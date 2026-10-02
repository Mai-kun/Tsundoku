using System.Data.Common;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace MediaTracker.Server.Infrastructure;

public sealed class SqliteConnectionInterceptor : DbConnectionInterceptor
{
    // journal_mode is a persistent property of the database file, not of a connection, so re-running
    // it on every open is pure overhead. The other two are per-connection and must be reapplied.
    private const string ConnectionPragmas = "PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000;";
    private const string JournalPragma = "PRAGMA journal_mode = WAL;";

    private static int journalModeApplied;

    public override void ConnectionOpened(
        DbConnection connection,
        ConnectionEndEventData eventData)
    {
        var pragmas = Interlocked.Exchange(ref journalModeApplied, 1) == 0
            ? JournalPragma + ConnectionPragmas
            : ConnectionPragmas;

        using var command = connection.CreateCommand();
        command.CommandText = pragmas;
        command.ExecuteNonQuery();
    }

    public override async Task ConnectionOpenedAsync(
        DbConnection connection,
        ConnectionEndEventData eventData,
        CancellationToken cancellationToken = default)
    {
        var pragmas = Interlocked.Exchange(ref journalModeApplied, 1) == 0
            ? JournalPragma + ConnectionPragmas
            : ConnectionPragmas;

        using var command = connection.CreateCommand();
        command.CommandText = pragmas;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}