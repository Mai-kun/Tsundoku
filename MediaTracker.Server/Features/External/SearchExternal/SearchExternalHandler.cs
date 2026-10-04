using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.External.SearchExternal;

/// <param name="Source">
/// When set, search that provider alone instead of cascading through the configured priorities.
/// The relink dialog needs this: the user picks which service to look for the replacement in.
/// </param>
public sealed record SearchExternalQuery(string? Type, string? Query, string? Source = null);

public interface ISearchExternalHandler
{
    Task<Result<IReadOnlyList<ExternalMediaDto>>> HandleAsync(SearchExternalQuery query, CancellationToken ct);
}

/// <summary>
/// Fans the search out across the sources of one media type. The aggregator applies the per-source
/// deadline and the cascade order, so this slice only owns the input contract.
/// </summary>
public sealed class SearchExternalHandler(MetadataAggregatorService aggregator) : ISearchExternalHandler
{
    public async Task<Result<IReadOnlyList<ExternalMediaDto>>> HandleAsync(
        SearchExternalQuery query,
        CancellationToken ct)
    {
        var normalizedType = SearchTypes.Normalize(query.Type);
        var normalizedQuery = query.Query?.Trim() ?? string.Empty;

        var errors = new Dictionary<string, string[]>();

        if (!SearchTypes.IsSupported(normalizedType))
        {
            errors["type"] = [$"Type must be one of: {string.Join(", ", SearchTypes.Supported)}."];
        }

        if (normalizedQuery.Length < 2)
        {
            errors["query"] = ["Query must contain at least 2 characters."];
        }

        if (errors.Count > 0)
        {
            return Result<IReadOnlyList<ExternalMediaDto>>.Failure(Error.Validation(errors));
        }

        var results = string.IsNullOrWhiteSpace(query.Source)
            ? await aggregator.SearchAsync(normalizedType, normalizedQuery, ct)
            : await aggregator.SearchSourceAsync(normalizedType, normalizedQuery, query.Source, ct);

        return Result<IReadOnlyList<ExternalMediaDto>>.Success(results);
    }
}
