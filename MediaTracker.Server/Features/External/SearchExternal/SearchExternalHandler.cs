using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

namespace MediaTracker.Server.Features.External.SearchExternal;

/// <param name="Source">
/// When set, search that provider alone instead of cascading through the configured priorities.
/// The relink dialog needs this: the user picks which service to look for the replacement in.
/// </param>
/// <param name="ByCreator">
/// The query names a studio/author, not a title: providers ask their upstream creator index and
/// results are filtered to works the creator actually made.
/// </param>
public sealed record SearchExternalQuery(string? Type, string? Query, string? Source = null, bool ByCreator = false);

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

        if (normalizedType == "book"
            || string.Equals(query.Source, "sociallib", StringComparison.OrdinalIgnoreCase)
            || string.Equals(query.Source, "ranobelib", StringComparison.OrdinalIgnoreCase)
            || string.Equals(query.Source, "shikimori", StringComparison.OrdinalIgnoreCase))
        {
            var stripped = MediaTitleHelper.StripGarbageSuffixes(normalizedQuery);
            if (!string.IsNullOrWhiteSpace(stripped))
            {
                normalizedQuery = stripped;
            }
        }

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

        // ISBN search handler: if query is an ISBN and general mode ("All" / null) or Book category is selected,
        // execute search in OpenLibrary AND LiveLib concurrently and merge results under Book.
        if (IsIsbnQuery(normalizedQuery, out var cleanIsbn) &&
            (string.IsNullOrWhiteSpace(query.Source) || string.Equals(query.Source, "all", StringComparison.OrdinalIgnoreCase)) &&
            (normalizedType == SearchTypes.All || normalizedType == MediaType.Book))
        {
            var openLibTask = SafeSearchSourceAsync("openlibrary", cleanIsbn, ct);
            var liveLibTask = SafeSearchSourceAsync("livelib", cleanIsbn, ct);

            await Task.WhenAll(openLibTask, liveLibTask);

            var openLibResults = await openLibTask;
            var liveLibResults = await liveLibTask;

            var combined = new List<ExternalMediaDto>(openLibResults.Count + liveLibResults.Count);
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var item in openLibResults.Concat(liveLibResults))
            {
                var bookItem = item.Type == MediaType.Book ? item : item with { Type = MediaType.Book };
                var key = $"{bookItem.ExternalSource}:{bookItem.ExternalId}";
                if (seen.Add(key))
                {
                    combined.Add(bookItem);
                }
            }

            return Result<IReadOnlyList<ExternalMediaDto>>.Success(combined);
        }

        var results = string.IsNullOrWhiteSpace(query.Source)
            ? await aggregator.SearchAsync(normalizedType, normalizedQuery, ct, query.ByCreator)
            : await aggregator.SearchSourceAsync(normalizedType, normalizedQuery, query.Source, ct, query.ByCreator);

        // Ensure each item has a strictly valid Type so grouping in UI never falls back to defaults
        var mappedResults = results.Select(item =>
        {
            if (string.Equals(item.ExternalSource, "LiveLib", StringComparison.OrdinalIgnoreCase))
            {
                return item.Type == MediaType.Book ? item : item with { Type = MediaType.Book };
            }

            if (string.IsNullOrWhiteSpace(item.Type))
            {
                return item with { Type = normalizedType == SearchTypes.All ? MediaType.Book : normalizedType };
            }

            return item;
        }).ToList();

        return Result<IReadOnlyList<ExternalMediaDto>>.Success(mappedResults);
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SafeSearchSourceAsync(
        string source,
        string isbn,
        CancellationToken ct)
    {
        try
        {
            return await aggregator.SearchSourceAsync(MediaType.Book, isbn, source, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return [];
        }
    }

    internal static bool IsIsbnQuery(string query, out string cleanIsbn)
    {
        cleanIsbn = Regex.Replace(query.Trim(), @"[\s\-]", "");
        if (cleanIsbn.StartsWith("isbn:", StringComparison.OrdinalIgnoreCase))
        {
            cleanIsbn = cleanIsbn[5..];
        }

        return Regex.IsMatch(cleanIsbn, @"^(?:\d{9}[\dxX]|\d{13})$");
    }
}
