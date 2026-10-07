using System.Diagnostics;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class MetadataAggregatorService(
    IMetadataProviderResolver providerResolver,
    ISourcePriorityService priorityService,
    IMemoryCache cache,
    ILogger<MetadataAggregatorService> logger)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    /// <summary>Per-source budget for one enrichment query.</summary>
    private static readonly TimeSpan EnrichmentQueryTimeout = TimeSpan.FromSeconds(4);

    /// <summary>Per-source budget for one search attempt in the fallback cascade.</summary>
    private static readonly TimeSpan SearchFallbackTimeout = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Ceiling for a whole fan-out. The per-query timeout alone lets a request hold a thread for as
    /// long as the slowest source, so the batch gets an explicit, smaller deadline of its own.
    /// </summary>
    private static readonly TimeSpan EnrichmentBatchTimeout = TimeSpan.FromSeconds(3);

    private static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    public async ValueTask<IReadOnlyList<ExternalMediaDto>> SearchAsync(string type, string query, CancellationToken ct)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type);
        var normalizedQuery = query.Trim();
        var cacheKey = $"search:{(normalizedType.Length == 0 ? "all" : normalizedType)}:{normalizedQuery.ToLowerInvariant()}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        var results = normalizedType is "all" or ""
            ? await SearchAllAsync(normalizedQuery, ct)
            : await SearchProviderWithFallbackAsync(normalizedType, normalizedQuery, ct);

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }

    /// <summary>
    /// Searches one named provider instead of cascading through the priorities. The relink dialog
    /// uses it: the user decides which service the replacement is looked up in, so a cascade that
    /// silently answers from a different provider would defeat the point.
    /// </summary>
    public async Task<IReadOnlyList<ExternalMediaDto>> SearchSourceAsync(
        string type,
        string query,
        string source,
        CancellationToken ct)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type);
        var normalizedQuery = query.Trim();
        var cacheKey = $"search:{normalizedType}:{normalizedQuery.ToLowerInvariant()}:{MediaMerger.NormalizeSourceKey(source)}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        IReadOnlyList<ExternalMediaDto> results = [];
        var provider = providerResolver.Resolve(normalizedType, source);
        if (provider is not null)
        {
            try
            {
                using var providerCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                providerCts.CancelAfter(SearchFallbackTimeout);
                var sw = Stopwatch.StartNew();
                results = await provider.SearchAsync(normalizedQuery, providerCts.Token);
                ExternalApiLog.Returned(logger, provider.Name, results.Count, sw.ElapsedMilliseconds);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                ExternalApiLog.Failed(logger, source, ex, $"search '{normalizedQuery}'");
                logger.LogDebug(ex, "[Aggregator] Source search '{Source}' failed for '{Query}': {Message}", source, normalizedQuery, ex.Message);
            }
        }
        else
        {
            logger.LogWarning("[Aggregator] Source '{Source}' is not registered for type '{Type}'", source, normalizedType);
        }

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }

    public async ValueTask<ExternalMediaDto?> GetDetailsAsync(string type, string externalId, string title, CancellationToken ct, string? source = null)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type, source);
        var cacheKey = $"details:{normalizedType}:{MediaMerger.NormalizeSourceKey(source ?? string.Empty)}:{externalId}:{title}";
        if (cache.TryGetValue(cacheKey, out ExternalMediaDto? cached) && cached is not null)
        {
            return cached;
        }

        ExternalMediaDto? initialDetails = null;

        if (!string.IsNullOrWhiteSpace(source))
        {
            // An explicit source is a hard request: never silently substitute a different
            // provider's entity for it, the caller's id only means something to that source.
            var directProvider = providerResolver.Resolve(normalizedType, source);
            if (directProvider is null)
            {
                logger.LogWarning("[Aggregator] Source '{Source}' is not registered for type '{Type}'", source, normalizedType);
                return null;
            }

            try
            {
                ExternalApiLog.Querying(logger, source, normalizedType, DetailsLogLabel(externalId, title));
                initialDetails = await directProvider.GetDetailsAsync(externalId, title, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                ExternalApiLog.Failed(logger, source, ex, $"details '{externalId}'");
                logger.LogWarning(ex, "[Aggregator] Direct provider '{Source}' GetDetailsAsync failed: {Message}", source, ex.Message);
                throw new SourceUnavailableException(source, ex.Message, ex);
            }

            if (initialDetails is null)
            {
                return null;
            }

            var enriched = await EnrichAsync(initialDetails, normalizedType, ct);
            cache.Set(cacheKey, enriched, CacheDuration);
            return enriched;
        }

        var prioritySources = await priorityService.GetPrioritiesAsync(normalizedType, ct);
        foreach (var src in prioritySources)
        {
            var provider = providerResolver.Resolve(normalizedType, src);
            if (provider is null) continue;

            try
            {
                initialDetails = await provider.GetDetailsAsync(externalId, title, ct);
                if (initialDetails is not null) break;
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "[Aggregator] Priority provider '{Source}' GetDetailsAsync failed: {Message}", src, ex.Message);
            }
        }

        if (initialDetails is null) return null;

        var result = await EnrichAsync(initialDetails, normalizedType, ct);
        cache.Set(cacheKey, result, CacheDuration);
        return result;
    }

    public async Task<ExternalMediaDto> EnrichAsync(ExternalMediaDto details, string type, CancellationToken ct)
    {
        var current = details;
        var ratings = details.Ratings is not null ? new List<ExternalRatingDto>(details.Ratings) : [];
        if (ratings.Count == 0 && details.Rating.HasValue && !string.IsNullOrWhiteSpace(details.ExternalSource))
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = details.ExternalSource,
                Rating = details.Rating.Value,
                Votes = details.RatingVotes
            });
        }

        var prioritySources = await priorityService.GetPrioritiesAsync(type, ct);
        var candidateSources = new List<string>();

        foreach (var source in prioritySources)
        {
            var normalizedSource = MediaMerger.NormalizeSourceKey(source);
            bool hasRatingFromSource = ratings.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == normalizedSource);
            bool needsData = MediaMerger.HasMissingMetadata(current, type);

            if (!hasRatingFromSource || needsData)
            {
                candidateSources.Add(source);
            }
        }

        if (candidateSources.Count == 0)
        {
            return current with { Ratings = ratings };
        }

        var tasks = candidateSources.Select(source => QuerySourceEnrichmentAsync(source, type, current, ratings, ct));

        // A hung provider must not hold the request open: the batch deadline aborts whatever has not
        // answered yet, and the partial answers already collected are still merged below.
        using var batchCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        batchCts.CancelAfter(EnrichmentBatchTimeout);

        SourceEnrichmentResult[] results;
        try
        {
            results = await Task.WhenAll(tasks).WaitAsync(batchCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogDebug(
                "[Aggregator] Enrichment batch exceeded {Timeout}s for '{Title}'; merging the answers that arrived",
                EnrichmentBatchTimeout.TotalSeconds,
                current.Title);
            return current with { Ratings = ratings };
        }

        var resultMap = results.ToDictionary(r => r.Source, StringComparer.OrdinalIgnoreCase);

        foreach (var source in candidateSources)
        {
            if (!resultMap.TryGetValue(source, out var res)) continue;

            if (res.MatchedMedia is not null)
            {
                current = MediaMerger.Merge(current, res.MatchedMedia);
            }

            if (res.Rating is not null && !ratings.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == MediaMerger.NormalizeSourceKey(res.Rating.Source)))
            {
                ratings.Add(res.Rating);
            }
        }

        return current with { Ratings = ratings };
    }

    private async Task<SourceEnrichmentResult> QuerySourceEnrichmentAsync(
        string source,
        string type,
        ExternalMediaDto current,
        List<ExternalRatingDto> existingRatings,
        CancellationToken ct)
    {
        var normalizedSource = MediaMerger.NormalizeSourceKey(source);
        bool hasRatingFromSource = existingRatings.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == normalizedSource);
        bool needsData = MediaMerger.HasMissingMetadata(current, type);

        var provider = providerResolver.Resolve(type, source);
        if (provider is null)
        {
            return new SourceEnrichmentResult(source, null, null);
        }

        try
        {
            using var queryCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            queryCts.CancelAfter(EnrichmentQueryTimeout);

            var sw = Stopwatch.StartNew();
            var search = await provider.SearchAsync(current.Title, queryCts.Token);
            ExternalApiLog.Returned(logger, provider.Name, search.Count, sw.ElapsedMilliseconds);

            // A Russian title answers nothing on AniList/Shikimori, which index romaji and English
            // names: "Гачиакута" finds no rating while its romaji spelling ("Gachiakuta") does, so
            // an empty first search retries with the alternate spellings before giving up on the source.
            foreach (var altTitle in AlternativeTitles(current))
            {
                if (search.Count > 0)
                {
                    break;
                }

                search = await provider.SearchAsync(altTitle, queryCts.Token);
                ExternalApiLog.Returned(logger, provider.Name, search.Count, sw.ElapsedMilliseconds);
            }

            var match = search.FirstOrDefault(s => s.Title.Equals(current.Title, StringComparison.OrdinalIgnoreCase))
                        ?? (search.Count > 0 ? search[0] : null);

            if (match is not null)
            {
                var fullMatch = match;
                bool shouldFetchDetails = !string.IsNullOrWhiteSpace(match.ExternalId) &&
                    (needsData || (!hasRatingFromSource && (match.Rating == null || match.Rating <= 0)));
                if (shouldFetchDetails)
                {
                    try
                    {
                        var deeper = await provider.GetDetailsAsync(match.ExternalId, current.Title, queryCts.Token);
                        if (deeper is not null) fullMatch = deeper;
                    }
                    catch (Exception ex)
                    {
                        logger.LogDebug(ex, "[Aggregator] Failed deeper details from '{Source}' for '{Title}': {Message}", source, current.Title, ex.Message);
                    }
                }

                ExternalRatingDto? ratingDto = null;
                if (!hasRatingFromSource)
                {
                    var sourceRating = fullMatch.Ratings?.FirstOrDefault(r => MediaMerger.NormalizeSourceKey(r.Source) == normalizedSource);
                    var ratingVal = sourceRating?.Rating ?? fullMatch.Rating ?? match.Rating;
                    var ratingVotes = sourceRating?.Votes ?? fullMatch.RatingVotes ?? match.RatingVotes;

                    if (ratingVal is > 0)
                    {
                        ratingDto = new ExternalRatingDto
                        {
                            Source = sourceRating?.Source ?? fullMatch.ExternalSource ?? match.ExternalSource ?? MediaMerger.GetCanonicalSourceName(source),
                            Rating = ratingVal.Value,
                            Votes = ratingVotes
                        };
                    }
                    else
                    {
                        ratingDto = new ExternalRatingDto
                        {
                            Source = MediaMerger.GetCanonicalSourceName(source),
                            Rating = 0,
                            Votes = null
                        };
                    }
                }

                return new SourceEnrichmentResult(source, fullMatch, ratingDto);
            }
            else if (!hasRatingFromSource)
            {
                return new SourceEnrichmentResult(source, null, new ExternalRatingDto
                {
                    Source = MediaMerger.GetCanonicalSourceName(source),
                    Rating = 0,
                    Votes = null
                });
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, source, ex, $"enrichment '{current.Title}'");
            logger.LogDebug(ex, "[Aggregator] Enrichment query failed for source '{Source}' and title '{Title}': {Message}", source, current.Title, ex.Message);
            if (!hasRatingFromSource)
            {
                return new SourceEnrichmentResult(source, null, new ExternalRatingDto
                {
                    Source = MediaMerger.GetCanonicalSourceName(source),
                    Rating = 0,
                    Votes = null
                });
            }
        }

        return new SourceEnrichmentResult(source, null, null);
    }

    /// <summary>
    /// The stored title's alternate spellings for the retry search: romaji first (what AniList and
    /// Shikimori actually match on), then the native/English alt. Duplicates of the title that was
    /// already tried are skipped.
    /// </summary>
    private static IEnumerable<string> AlternativeTitles(ExternalMediaDto current)
    {
        if (!string.IsNullOrWhiteSpace(current.RomajiTitle)
            && !current.RomajiTitle.Equals(current.Title, StringComparison.OrdinalIgnoreCase))
        {
            yield return current.RomajiTitle;
        }

        if (!string.IsNullOrWhiteSpace(current.OriginalTitle)
            && !current.OriginalTitle.Equals(current.Title, StringComparison.OrdinalIgnoreCase))
        {
            yield return current.OriginalTitle;
        }
    }

    /// <summary>
    /// The id is the fallback label: a details request may carry no title, and an empty query in the
    /// log is the one thing that cannot be traced back to the call that caused it.
    /// </summary>
    private static string DetailsLogLabel(string externalId, string title) =>
        !string.IsNullOrWhiteSpace(title) ? title
        : !string.IsNullOrWhiteSpace(externalId) ? $"id:{externalId}"
        : "(no id, no title)";

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderWithFallbackAsync(string type, string query, CancellationToken ct)
    {
        var prioritySources = await priorityService.GetPrioritiesAsync(type, ct);

        foreach (var source in prioritySources)
        {
            ct.ThrowIfCancellationRequested();

            var provider = providerResolver.Resolve(type, source);
            if (provider is null)
            {
                continue;
            }

            var sw = Stopwatch.StartNew();
            try
            {
                using var providerCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                providerCts.CancelAfter(SearchFallbackTimeout);
                var results = await provider.SearchAsync(query, providerCts.Token);
                ExternalApiLog.Returned(logger, provider.Name, results.Count, sw.ElapsedMilliseconds);
                if (results.Count > 0)
                {
                    return results;
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                ExternalApiLog.Failed(logger, source, ex, $"fallback search '{query}'");
                logger.LogDebug(ex, "[Aggregator] Search fallback: source '{Source}' failed for '{Query}': {Message}", source, query, ex.Message);
            }
        }

        return [];
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchAllAsync(string query, CancellationToken ct)
    {
        var tasks = AllTypes.Select(type => SearchProviderSafeAsync(type, query, ct));
        var groups = await Task.WhenAll(tasks);

        return [.. groups.SelectMany(group => group)];
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderSafeAsync(string type, string query, CancellationToken ct)
    {
        try
        {
            return await SearchProviderWithFallbackAsync(type, query, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "[Aggregator] Safe search for type '{Type}' failed: {Message}", type, ex.Message);
            return [];
        }
    }

    private sealed record SourceEnrichmentResult(string Source, ExternalMediaDto? MatchedMedia, ExternalRatingDto? Rating);
}
