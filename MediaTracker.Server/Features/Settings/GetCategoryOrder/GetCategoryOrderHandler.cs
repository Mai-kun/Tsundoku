using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.GetCategoryOrder;

public interface IGetCategoryOrderHandler
{
    Task<Result<string[]>> HandleAsync(CancellationToken ct);
}

/// <summary>The order the search modal lists its media-type groups in.</summary>
public sealed class GetCategoryOrderHandler(AppDbContext db) : IGetCategoryOrderHandler
{
    private const string SettingKey = "SearchCategoryOrder";

    private static readonly string[] DefaultOrder =
        ["anime", "movie", "tvshow", "manga", "game", "book"];

    public async Task<Result<string[]>> HandleAsync(CancellationToken ct)
    {
        var stored = await AppSettingStore.ReadAsync(db, SettingKey, ct);
        var parsed = JsonSettings.TryDeserialize<string[]>(stored);

        return Result<string[]>.Success(parsed is { Length: > 0 } ? parsed : DefaultOrder);
    }
}
