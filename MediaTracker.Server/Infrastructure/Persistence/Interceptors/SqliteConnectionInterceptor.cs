using System.Data.Common;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace MediaTracker.Server.Infrastructure.Persistence.Interceptors;

public sealed class SqliteConnectionInterceptor : DbConnectionInterceptor
{
    /// <summary>
    /// Values applied. Kept visible so <c>--selfcheck</c> can assert the production tuning is intact.
    /// </summary>
    public static class Pragmas
    {
        /// <summary>WAL is a persistent property of the database file, so it runs only on the first open.</summary>
        public const string JournalMode = "WAL";

        public const string Synchronous = "NORMAL";

        public const int BusyTimeoutMilliseconds = 5000;

        /// <summary>Negative means kibibytes rather than pages: about 64 MB of page cache.</summary>
        public const int CacheSizeKibibytes = -64000;
    }

    // journal_mode is a persistent property of the database file, not of a connection, so re-running
    // it on every open is pure overhead. The rest are per-connection and must be reapplied.
    public static readonly string ConnectionPragmas =
        $"PRAGMA synchronous = {Pragmas.Synchronous}; " +
        $"PRAGMA busy_timeout = {Pragmas.BusyTimeoutMilliseconds}; " +
        $"PRAGMA cache_size = {Pragmas.CacheSizeKibibytes};";

    public static readonly string JournalPragma = $"PRAGMA journal_mode = {Pragmas.JournalMode};";

    private static int journalModeApplied;

    /// <summary>The script a connection open runs; the journal pragma is included only once per process.</summary>
    public static string BuildPragmaScript() =>
        Interlocked.Exchange(ref journalModeApplied, 1) == 0
            ? JournalPragma + ConnectionPragmas
            : ConnectionPragmas;

    public override void ConnectionOpened(
        DbConnection connection,
        ConnectionEndEventData eventData)
    {
        using var command = connection.CreateCommand();
        command.CommandText = BuildPragmaScript();
        command.ExecuteNonQuery();
    }

    public override async Task ConnectionOpenedAsync(
        DbConnection connection,
        ConnectionEndEventData eventData,
        CancellationToken cancellationToken = default)
    {
        using var command = connection.CreateCommand();
        command.CommandText = BuildPragmaScript();
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
