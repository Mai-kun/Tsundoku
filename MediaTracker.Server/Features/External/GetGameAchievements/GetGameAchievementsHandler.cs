using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.GetGameAchievements;

public sealed record GetGameAchievementsQuery(
    string? SteamAppId,
    string? RawgId,
    string? Title,
    string? ExternalSource,
    string? ExternalId);

public interface IGetGameAchievementsHandler
{
    Task<Result<object>> HandleAsync(GetGameAchievementsQuery query, CancellationToken ct);
}

/// <summary>
/// Live re-read of the provider's list; the creation pipeline already stores its own copy on the
/// row (see <see cref="Features.Jobs.MediaEnrichmentJob"/>), so this backs the explicit refresh.
/// </summary>
public sealed class GetGameAchievementsHandler(RawgGameService gameService) : IGetGameAchievementsHandler
{
    public async Task<Result<object>> HandleAsync(GetGameAchievementsQuery query, CancellationToken ct)
    {
        var achievements = await gameService.GetAchievementsAsync(
            query.SteamAppId,
            query.RawgId,
            query.Title,
            query.ExternalSource,
            query.ExternalId,
            ct);

        return Result<object>.Success(achievements);
    }
}
