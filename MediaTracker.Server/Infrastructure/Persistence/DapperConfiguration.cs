using System;
using System.Data;
using System.Globalization;
using Dapper;

[module: Dapper.DapperAot]

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Entry point for Dapper.AOT. The <see cref="DapperAotAttribute"/> on this module tells the
/// Dapper.AOT source generator to emit AOT-safe interceptors for every Dapper call site in this
/// assembly, so the server can run under NativeAOT without reflection.
/// </summary>
public static class DapperConfiguration
{
    /// <summary>
    /// SQLite stores Guid as TEXT (36-char string), matching EF Core SQLite conventions.
    /// Dapper's built-in Guid handler expects binary, so we register a text-based handler.
    /// </summary>
    public sealed class GuidHandler : SqlMapper.TypeHandler<Guid>
    {
        public override Guid Parse(object value) =>
            value switch
            {
                string s => Guid.Parse(s),
                byte[] bytes => new Guid(bytes),
                _ => throw new InvalidCastException($"Cannot convert {value?.GetType()} to Guid.")
            };

        public override void SetValue(IDbDataParameter parameter, Guid value) =>
            parameter.Value = value.ToString();
    }

    /// <summary>Nullable Guid handler for TEXT storage.</summary>
    public sealed class GuidNullableHandler : SqlMapper.TypeHandler<Guid?>
    {
        public override Guid? Parse(object value)
        {
            if (value == null || value == DBNull.Value) return null;
            return value switch
            {
                string s => Guid.Parse(s),
                byte[] bytes => new Guid(bytes),
                _ => throw new InvalidCastException($"Cannot convert {value.GetType()} to Guid?.")
            };
        }

        public override void SetValue(IDbDataParameter parameter, Guid? value) =>
            parameter.Value = value is { } guid ? (object)guid.ToString() : DBNull.Value;
    }

    /// <summary>
    /// DateTime is stored as TEXT (ISO 8601) by EF Core SQLite; register a handler so Dapper
    /// reads/writes it in the same format.
    /// </summary>
    public sealed class DateTimeHandler : SqlMapper.TypeHandler<DateTime>
    {
        public override DateTime Parse(object value) =>
            value switch
            {
                string s => DateTime.Parse(s, null, DateTimeStyles.RoundtripKind),
                _ => throw new InvalidCastException($"Cannot convert {value?.GetType()} to DateTime.")
            };

        public override void SetValue(IDbDataParameter parameter, DateTime value) =>
            parameter.Value = value.ToString("o");
    }

    /// <summary>Nullable DateTime handler for TEXT storage.</summary>
    public sealed class DateTimeNullableHandler : SqlMapper.TypeHandler<DateTime?>
    {
        public override DateTime? Parse(object value)
        {
            if (value == null || value == DBNull.Value) return null;
            return value switch
            {
                string s => DateTime.Parse(s, null, DateTimeStyles.RoundtripKind),
                _ => throw new InvalidCastException($"Cannot convert {value.GetType()} to DateTime?.")
            };
        }

        public override void SetValue(IDbDataParameter parameter, DateTime? value) =>
            parameter.Value = value is { } dt ? (object)dt.ToString("o") : DBNull.Value;
    }

    static DapperConfiguration()
    {
        EnsureInitialized();
    }

    public static void EnsureInitialized()
    {
        // Type handlers are registered in the static constructor; this method exists
        // purely to trigger that constructor from AppDbContext.
    }
}
