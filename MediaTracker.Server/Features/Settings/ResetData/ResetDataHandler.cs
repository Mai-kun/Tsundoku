using Dapper;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.Settings.ResetData;

public sealed record ResetDataRequest(bool KeepApiKeys = true);

public interface IResetDataHandler
{
    Task<Result> HandleAsync(ResetDataRequest request, CancellationToken ct);
}

public sealed class ResetDataHandler(
    AppDbContext db,
    AppPaths appPaths,
    IOptions<ExternalApiOptions> apiOptions,
    IMemoryCache cache) : IResetDataHandler
{
    public async Task<Result> HandleAsync(ResetDataRequest request, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        using var tx = conn.BeginTransaction();

        try
        {
            // A pending local transaction makes Dapper throw unless every command
            // explicitly joins it (the connection's ambient transaction is not picked up).
            await conn.ExecuteAsync("DELETE FROM CustomListItems;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM CustomLists;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM Events;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM TvSeasons;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM MangaVolumes;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM MediaItems;", transaction: tx);
            await conn.ExecuteAsync("DELETE FROM Franchises;", transaction: tx);

            if (request.KeepApiKeys)
            {
                await conn.ExecuteAsync(
                    "DELETE FROM Settings WHERE Key IN ('SourcePriority', 'DisabledSources', 'SearchCategoryOrder');",
                    transaction: tx);
            }
            else
            {
                await conn.ExecuteAsync("DELETE FROM Settings;", transaction: tx);
            }

            tx.Commit();
        }
        catch
        {
            tx.Rollback();
            throw;
        }

        if (!request.KeepApiKeys)
        {
            apiOptions.Value.ClearKeys();
        }

        ResetDirectory(appPaths.MediaDirectory);
        ResetDirectory(appPaths.CoversDirectory);

        await conn.ExecuteAsync("VACUUM;");

        if (cache is MemoryCache memoryCache)
        {
            memoryCache.Compact(1.0);
        }

        return Result.Success();
    }

    private static void ResetDirectory(string path)
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }

        Directory.CreateDirectory(path);
    }
}
