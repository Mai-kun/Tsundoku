using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.GetSourcePriority;

public interface IGetSourcePriorityHandler
{
    Task<Result<Dictionary<string, string[]>>> HandleAsync(CancellationToken ct);
}

public sealed class GetSourcePriorityHandler(AppDbContext db) : IGetSourcePriorityHandler
{
    private const string SettingKey = "SourcePriority";

    public async Task<Result<Dictionary<string, string[]>>> HandleAsync(CancellationToken ct)
    {
        var stored = await AppSettingStore.ReadAsync(db, SettingKey, ct);
        var merged = SourcePriorityService.MergeWithDefaults(JsonSettings.
            TryDeserialize<Dictionary<string, string[]>>(stored));

        // Newly shipped sources get folded into the saved order on first read, so persist the result.
        var json = JsonSettings.Serialize(merged);
        if (stored is not null && stored != json)
        {
            await AppSettingStore.SetAsync(db, SettingKey, json, ct);
        }

        return Result<Dictionary<string, string[]>>.Success(merged);
    }
}
