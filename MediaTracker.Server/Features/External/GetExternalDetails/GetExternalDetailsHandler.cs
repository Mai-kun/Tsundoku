using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.GetExternalDetails;

public sealed record GetExternalDetailsQuery(string? Type, string? Id, string? Title, string? Source);

public interface IGetExternalDetailsHandler
{
    Task<Result<ExternalMediaDto>> HandleAsync(GetExternalDetailsQuery query, CancellationToken ct);
}

/// <summary>
/// One source's record for one entity, used by the search modal's preview pane. An explicit source is
/// a hard request: the aggregator never substitutes a different provider for it.
/// </summary>
public sealed class GetExternalDetailsHandler(MetadataAggregatorService aggregator) : IGetExternalDetailsHandler
{
    public async Task<Result<ExternalMediaDto>> HandleAsync(
        GetExternalDetailsQuery query,
        CancellationToken ct)
    {
        var normalizedType = string.IsNullOrWhiteSpace(query.Type) ? "anime" : query.Type.Trim();
        var normalizedId = query.Id?.Trim() ?? string.Empty;
        var normalizedTitle = query.Title?.Trim() ?? string.Empty;

        if (string.IsNullOrWhiteSpace(normalizedId) && string.IsNullOrWhiteSpace(normalizedTitle))
        {
            return Result<ExternalMediaDto>.Failure(
                Error.Validation("Either id or title is required."));
        }

        var details = await aggregator.GetDetailsAsync(
            normalizedType,
            normalizedId,
            normalizedTitle,
            ct,
            query.Source);

        return details is null
            ? Result<ExternalMediaDto>.Failure(
                Error.NotFound($"No external record was found for '{normalizedTitle}'."))
            : Result<ExternalMediaDto>.Success(details);
    }
}
