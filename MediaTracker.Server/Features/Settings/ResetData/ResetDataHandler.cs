using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
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
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        await db.CustomListItems.ExecuteDeleteAsync(ct);
        await db.CustomLists.ExecuteDeleteAsync(ct);
        await db.Events.ExecuteDeleteAsync(ct);
        await db.TvSeasons.ExecuteDeleteAsync(ct);
        await db.MangaVolumes.ExecuteDeleteAsync(ct);
        await db.MediaItems.ExecuteDeleteAsync(ct);
        await db.Franchises.ExecuteDeleteAsync(ct);

        if (request.KeepApiKeys)
        {
            await db.Settings
                .Where(setting => setting.Key == "SourcePriority"
                    || setting.Key == "DisabledSources"
                    || setting.Key == "SearchCategoryOrder")
                .ExecuteDeleteAsync(ct);
        }
        else
        {
            await db.Settings.ExecuteDeleteAsync(ct);
        }

        await transaction.CommitAsync(ct);

        if (!request.KeepApiKeys)
        {
            apiOptions.Value.ClearKeys();
        }

        ResetDirectory(appPaths.MediaDirectory);
        ResetDirectory(appPaths.CoversDirectory);

        await db.Database.ExecuteSqlRawAsync("VACUUM;", ct);

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
