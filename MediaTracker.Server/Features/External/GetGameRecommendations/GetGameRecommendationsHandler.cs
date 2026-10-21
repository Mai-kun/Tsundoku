using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.GetGameRecommendations;

public sealed record GetGameRecommendationsQuery(
    string? RawgId,
    string? Title,
    string? ExternalSource,
    string? ExternalId);

public interface IGetGameRecommendationsHandler
{
    Task<Result<object>> HandleAsync(GetGameRecommendationsQuery query, CancellationToken ct);
}

public sealed class GetGameRecommendationsHandler(RawgGameService gameService) : IGetGameRecommendationsHandler
{
    public async Task<Result<object>> HandleAsync(GetGameRecommendationsQuery query, CancellationToken ct)
    {
        var recommendations = await gameService.GetRecommendationsAsync(
            query.RawgId,
            query.Title,
            query.ExternalSource,
            query.ExternalId,
            ct);

        return Result<object>.Success(recommendations);
    }
}
