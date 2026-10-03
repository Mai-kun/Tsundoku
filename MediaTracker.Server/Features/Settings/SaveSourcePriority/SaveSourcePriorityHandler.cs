using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.SaveSourcePriority;

public sealed record SaveSourcePriorityCommand(Dictionary<string, string[]> Priority);

public interface ISaveSourcePriorityHandler
{
    Task<Result<Dictionary<string, string[]>>> HandleAsync(
        SaveSourcePriorityCommand command,
        CancellationToken ct);
}

public sealed class SaveSourcePriorityHandler(
    AppDbContext db,
    ISourcePriorityService priorityService) : ISaveSourcePriorityHandler
{
    private const string SettingKey = "SourcePriority";

    public async Task<Result<Dictionary<string, string[]>>> HandleAsync(
        SaveSourcePriorityCommand command,
        CancellationToken ct)
    {
        if (command.Priority is null || command.Priority.Count == 0)
        {
            return Result<Dictionary<string, string[]>>.Failure(
                Error.Validation("A source priority order is required."));
        }

        await AppSettingStore.SetAsync(db, SettingKey, JsonSettings.Serialize(command.Priority), ct);
        priorityService.InvalidateCache();

        return Result<Dictionary<string, string[]>>.Success(command.Priority);
    }
}
