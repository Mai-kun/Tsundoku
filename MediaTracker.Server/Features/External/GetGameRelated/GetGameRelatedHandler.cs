using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.GetGameRelated;

public sealed record GetGameRelatedQuery(
    string? RawgId,
    string? Title,
    string? ExternalSource,
    string? ExternalId);

public interface IGetGameRelatedHandler
{
    Task<Result<object>> HandleAsync(GetGameRelatedQuery query, CancellationToken ct);
}

public sealed class GetGameRelatedHandler(RawgGameService gameService) : IGetGameRelatedHandler
{
    public async Task<Result<object>> HandleAsync(GetGameRelatedQuery query, CancellationToken ct)
    {
        var related = await gameService.GetRelatedAsync(
            query.RawgId,
            query.Title,
            query.ExternalSource,
            query.ExternalId,
            ct);

        return Result<object>.Success(related);
    }
}
