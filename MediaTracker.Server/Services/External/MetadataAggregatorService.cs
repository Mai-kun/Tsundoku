using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Services.External;

public sealed class MetadataAggregatorService(
    IMetadataProviderResolver providerResolver,
    ISourcePriorityService priorityService,
    IMemoryCache cache,
    ILogger<MetadataAggregatorService> logger)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);
    private static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string type, string query, CancellationToken ct)
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

    public async Task<ExternalMediaDto?> GetDetailsAsync(string type, string externalId, string title, CancellationToken ct, string? source = null)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type, source);
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
                initialDetails = await directProvider.GetDetailsAsync(externalId, title, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "[Aggregator] Direct provider '{Source}' GetDetailsAsync failed: {Message}", source, ex.Message);
                throw new SourceUnavailableException(source, ex.Message, ex);
            }

            if (initialDetails is null)
            {
                return null;
            }

            return await EnrichAsync(initialDetails, normalizedType, ct);
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

        return await EnrichAsync(initialDetails, normalizedType, ct);
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
        var results = await Task.WhenAll(tasks);
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
            queryCts.CancelAfter(TimeSpan.FromSeconds(4));

            var search = await provider.SearchAsync(current.Title, queryCts.Token);
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

            try
            {
                using var providerCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                providerCts.CancelAfter(TimeSpan.FromSeconds(3));
                var results = await provider.SearchAsync(query, providerCts.Token);
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
