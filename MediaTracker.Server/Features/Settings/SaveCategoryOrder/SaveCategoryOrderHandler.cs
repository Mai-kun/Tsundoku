using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.SaveCategoryOrder;

public sealed record SaveCategoryOrderCommand(string[] Order);

public interface ISaveCategoryOrderHandler
{
    Task<Result<string[]>> HandleAsync(SaveCategoryOrderCommand command, CancellationToken ct);
}

public sealed class SaveCategoryOrderHandler(AppDbContext db) : ISaveCategoryOrderHandler
{
    private const string SettingKey = "SearchCategoryOrder";

    public async Task<Result<string[]>> HandleAsync(SaveCategoryOrderCommand command, CancellationToken ct)
    {
        if (command.Order is null || command.Order.Length == 0)
        {
            return Result<string[]>.Failure(Error.Validation("A category order is required."));
        }

        await AppSettingStore.SetAsync(db, SettingKey, JsonSettings.Serialize(command.Order), ct);
        return Result<string[]>.Success(command.Order);
    }
}
