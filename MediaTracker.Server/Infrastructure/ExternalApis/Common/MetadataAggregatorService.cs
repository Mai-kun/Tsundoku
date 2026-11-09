using System.Collections.Concurrent;
using System.Diagnostics;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

public sealed class MetadataAggregatorService(
    IMetadataProviderResolver providerResolver,
    ISourcePriorityService priorityService,
    IMemoryCache cache,
    ILogger<MetadataAggregatorService> logger,
    OfflineDatabaseManager? offlineDbManager = null,
    IServiceScopeFactory? scopeFactory = null,
    RateLimitTracker? rateLimiter = null)
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

    /// <summary>Budget for a coalesced search fan-out, decoupled from any one client's lifetime.</summary>
    private static readonly TimeSpan CoalescedSearchTimeout = TimeSpan.FromSeconds(30);

    /// <summary>Budget for a coalesced details cascade plus enrichment.</summary>
    private static readonly TimeSpan CoalescedDetailsTimeout = TimeSpan.FromSeconds(90);

    /// <summary>
    /// Identical searches currently running upstream. A doubled request (two browser tabs, a
    /// React/Svelte re-render, a user retyping faster than the 10-minute cache expires) shares one
    /// fan-out instead of paying the external rate limit twice. Lazy + ExecutionAndPublication is
    /// required: a racing GetOrAdd may invoke the factory several times, and every invocation that
    /// started the task directly would have sent its own upstream fan-out.
    /// </summary>
    private readonly ConcurrentDictionary<string, Lazy<Task<IReadOnlyList<ExternalMediaDto>>>> inFlightSearches = new();

    /// <summary>Same coalescing for details: the UI fires several identical Detail loads in one second.</summary>
    private readonly ConcurrentDictionary<string, Lazy<Task<ExternalMediaDto?>>> inFlightDetails = new();

    private static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    private async ValueTask<bool> IsOfflineModeAsync(CancellationToken ct)
    {
        const string cacheKey = "settings:offline_mode";
        if (cache.TryGetValue(cacheKey, out bool isOffline))
        {
            return isOffline;
        }

        if (scopeFactory is null)
        {
            return false;
        }

        try
        {
            using var scope = scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var value = await AppSettingStore.ReadAsync(db, AppSettingStore.OfflineModeKey, ct);
            isOffline = string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
            cache.Set(cacheKey, isOffline, CacheDuration);
            return isOffline;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// The priority version rides in every cache key: a settings change (new source order, a source
    /// toggled off) bumps the version, so the old cached answers are unreachable without any
    /// manual eviction — the 10-minute search cache stops blending stale priorities.
    /// </summary>
    private string SearchCacheKey(string type, string query, bool byCreator) =>
        $"search:v{priorityService.Version}:{type}:{query.ToLowerInvariant()}{(byCreator ? ":creator" : "")}";

    private string DetailsCacheKey(string type, string source, string externalId, string title) =>
        $"details:v{priorityService.Version}:{type}:{MediaMerger.NormalizeSourceKey(source ?? string.Empty)}:{externalId}:{title}";

    public async ValueTask<IReadOnlyList<ExternalMediaDto>> SearchAsync(
        string type,
        string query,
        CancellationToken ct,
        bool byCreator = false)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type);
        var normalizedQuery = query.Trim();
        var cacheKey = SearchCacheKey(normalizedType.Length == 0 ? "all" : normalizedType, normalizedQuery, byCreator);

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        // Coalesce identical in-flight searches: the upstream fan-out runs once with its own
        // timeout, decoupled from the first caller — a client that disconnects mid-wait (the
        // browser aborting a keystroke's request) must not kill the shared work or its result.
        var shared = inFlightSearches.GetOrAdd(
            cacheKey,
            _ => new Lazy<Task<IReadOnlyList<ExternalMediaDto>>>(
                () => RunCoalescedSearchAsync(cacheKey, normalizedType, normalizedQuery, byCreator),
                LazyThreadSafetyMode.ExecutionAndPublication));

        return await shared.Value.WaitAsync(ct);
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> RunCoalescedSearchAsync(
        string cacheKey, string normalizedType, string normalizedQuery, bool byCreator)
    {
        using var timeout = new CancellationTokenSource(CoalescedSearchTimeout);
        try
        {
            var results = await SearchCoreAsync(normalizedType, normalizedQuery, timeout.Token, byCreator);
            cache.Set(cacheKey, results, CacheDuration);
            return results;
        }
        finally
        {
            // Unconditional on purpose: a torn removal only risks a duplicate upstream fan-out in
            // the rare race of two overlapping coalesced tasks, never a lost result — waiters hold
            // their task reference directly.
            inFlightSearches.TryRemove(cacheKey, out _);
        }
    }

    private async ValueTask<IReadOnlyList<ExternalMediaDto>> SearchCoreAsync(
        string normalizedType, string normalizedQuery, CancellationToken ct, bool byCreator)
    {
        if (await IsOfflineModeAsync(ct))
        {
            var offlineProvider = providerResolver.Resolve(normalizedType, "offline") as UniversalOfflineMetadataProvider
                ?? (offlineDbManager is not null ? new UniversalOfflineMetadataProvider(offlineDbManager) : null);

            IReadOnlyList<ExternalMediaDto> offlineResults = [];
            if (offlineProvider is not null)
            {
                var targetType = normalizedType is "all" or "" ? null : normalizedType;
                offlineResults = await offlineProvider.SearchAsync(normalizedQuery, targetType, ct);
            }

            return offlineResults;
        }

        IReadOnlyList<ExternalMediaDto> results = normalizedType is "all" or ""
            ? await SearchAllAsync(normalizedQuery, ct, byCreator)
            : await SearchProviderWithFallbackAsync(normalizedType, normalizedQuery, ct, byCreator);

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
        CancellationToken ct,
        bool byCreator = false)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type, source);
        var normalizedQuery = query.Trim();
        var cacheKey = $"search:v{priorityService.Version}:{normalizedType}:{normalizedQuery.ToLowerInvariant()}:{MediaMerger.NormalizeSourceKey(source)}{(byCreator ? ":creator" : "")}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalMediaDto>? cached) && cached is not null)
        {
            return cached;
        }

        if (source.StartsWith("offline:", StringComparison.OrdinalIgnoreCase))
        {
            var dbFileName = source["offline:".Length..].Trim();
            var targetType = normalizedType is "all" or "" ? null : normalizedType;
            IReadOnlyList<ExternalMediaDto> offlineResults = offlineDbManager is not null
                ? await offlineDbManager.ExecuteSearchInDatabaseAsync(dbFileName, targetType, normalizedQuery, 10, ct)
                : [];
            cache.Set(cacheKey, offlineResults, CacheDuration);
            return offlineResults;
        }

        if (await IsOfflineModeAsync(ct))
        {
            cache.Set(cacheKey, (IReadOnlyList<ExternalMediaDto>)[], CacheDuration);
            return [];
        }

        IReadOnlyList<ExternalMediaDto> results = [];
        var provider = providerResolver.Resolve(normalizedType, source);
        if (provider is not null)
        {
            try
            {
                using var providerCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                providerCts.CancelAfter(SearchFallbackTimeout);
                ExternalApiLog.Querying(logger, provider.Name, normalizedType, normalizedQuery);
                var sw = Stopwatch.StartNew();
                results = byCreator
                    ? await provider.SearchByCreatorAsync(normalizedQuery, providerCts.Token)
                    : await provider.SearchAsync(normalizedQuery, providerCts.Token);
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
                if (ex is HttpRequestException { StatusCode: System.Net.HttpStatusCode.TooManyRequests } or SourceUnavailableException ||
                    ex.Message.Contains("429"))
                {
                    throw new SourceUnavailableException(source, "429 Too Many Requests", ex);
                }
            }
        }
        else
        {
            logger.LogWarning("[Aggregator] Source '{Source}' is not registered for type '{Type}'", source, normalizedType);
        }

        cache.Set(cacheKey, results, CacheDuration);
        return results;
    }

    public async ValueTask<ExternalMediaDto?> GetDetailsAsync(
        string type,
        string externalId,
        string title,
        CancellationToken ct,
        string? source = null,
        IReadOnlyList<LinkedSourceDto>? knownSources = null,
        IReadOnlyList<string>? altTitles = null,
        TimeSpan? enrichTimeout = null,
        Action<IReadOnlyList<string>>? onSources = null)
    {
        var normalizedType = MediaMerger.NormalizeMediaType(type, source);
        var cacheKey = DetailsCacheKey(normalizedType, source ?? string.Empty, externalId, title);
        if (cache.TryGetValue(cacheKey, out ExternalMediaDto? cached) && cached is not null)
        {
            return cached;
        }

        if (!string.IsNullOrWhiteSpace(source) && source.StartsWith("offline:", StringComparison.OrdinalIgnoreCase))
        {
            var dbFileName = source["offline:".Length..].Trim();
            var targetType = normalizedType is "all" or "" ? null : normalizedType;
            var details = offlineDbManager is not null
                ? await offlineDbManager.GetDetailsInDatabaseAsync(dbFileName, externalId, title, targetType, ct)
                : null;
            if (details is not null)
            {
                cache.Set(cacheKey, details, CacheDuration);
            }
            return details;
        }

        // The related/preview panels and the detail view fire several identical Detail loads within
        // the same second (observed: every id hit AniList twice). Coalesce them into one cascade;
        // the shared task keeps running even if the first client disconnects.
        var shared = inFlightDetails.GetOrAdd(
            cacheKey,
            _ => new Lazy<Task<ExternalMediaDto?>>(
                () => RunCoalescedDetailsAsync(cacheKey, normalizedType, externalId, title, source, knownSources, altTitles, enrichTimeout, onSources),
                LazyThreadSafetyMode.ExecutionAndPublication));

        return await shared.Value.WaitAsync(ct);
    }

    private async Task<ExternalMediaDto?> RunCoalescedDetailsAsync(
        string cacheKey, string normalizedType, string externalId, string title, string? source,
        IReadOnlyList<LinkedSourceDto>? knownSources,
        IReadOnlyList<string>? altTitles,
        TimeSpan? enrichTimeout,
        Action<IReadOnlyList<string>>? onSources)
    {
        using var timeout = new CancellationTokenSource(CoalescedDetailsTimeout);
        try
        {
            var result = await DetailsCoreAsync(normalizedType, externalId, title, source, timeout.Token, knownSources, altTitles, enrichTimeout, onSources);
            if (result is not null)
            {
                cache.Set(cacheKey, result, CacheDuration);
            }

            return result;
        }
        finally
        {
            // Same trade-off as the search coalescing: a torn removal can only duplicate work in a
            // rare overlap, never lose a result.
            inFlightDetails.TryRemove(cacheKey, out _);
        }
    }

    private async ValueTask<ExternalMediaDto?> DetailsCoreAsync(
        string normalizedType, string externalId, string title, string? source, CancellationToken ct,
        IReadOnlyList<LinkedSourceDto>? knownSources = null,
        IReadOnlyList<string>? altTitles = null,
        TimeSpan? enrichTimeout = null,
        Action<IReadOnlyList<string>>? onSources = null)
    {
        if (await IsOfflineModeAsync(ct))
        {
            var offlineProvider = providerResolver.Resolve(normalizedType, "offline") as UniversalOfflineMetadataProvider
                ?? (offlineDbManager is not null ? new UniversalOfflineMetadataProvider(offlineDbManager) : null);

            var targetType = normalizedType is "all" or "" ? null : normalizedType;
            return offlineProvider is not null
                ? await offlineProvider.GetDetailsAsync(externalId, title, targetType, ct)
                : null;
        }

        ExternalMediaDto? initialDetails;

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

            return await EnrichAsync(initialDetails, normalizedType, ct, knownSources, altTitles, enrichTimeout, onSources);
        }

        initialDetails = null;
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
            catch (Exception ex)
            {
                logger.LogDebug(ex, "[Aggregator] Priority provider '{Source}' GetDetailsAsync failed: {Message}", src, ex.Message);
            }
        }

        if (initialDetails is null) return null;

        return await EnrichAsync(initialDetails, normalizedType, ct, knownSources, altTitles, enrichTimeout, onSources);
    }

    public async Task<ExternalMediaDto> EnrichAsync(
        ExternalMediaDto details,
        string type,
        CancellationToken ct,
        IReadOnlyList<LinkedSourceDto>? knownSources = null,
        IReadOnlyList<string>? altTitles = null,
        TimeSpan? timeout = null,
        Action<IReadOnlyList<string>>? onSources = null)
    {
        if (await IsOfflineModeAsync(ct))
        {
            return details;
        }

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

        var isClassicBook = MediaMerger.IsClassicBook(current);

        foreach (var source in prioritySources)
        {
            var normalizedSource = MediaMerger.NormalizeSourceKey(source);
            bool hasRatingFromSource = ratings.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == normalizedSource);
            bool needsData = MediaMerger.HasMissingMetadata(current, type);

            // Isolation Guard: if current is a classic book and source is an Asian novel/manga provider,
            // do not connect it for background auto-enrichment.
            if (isClassicBook && MediaMerger.IsAsianNovelOrMangaSource(source))
            {
                continue;
            }

            if (!hasRatingFromSource || needsData)
            {
                candidateSources.Add(source);
            }
        }

        if (candidateSources.Count == 0)
        {
            return current with { Ratings = ratings };
        }

        onSources?.Invoke(candidateSources);

        var queryTimeout = timeout ?? EnrichmentQueryTimeout;
        var tasks = candidateSources.Select(source =>
            QuerySourceEnrichmentAsync(source, type, current, ratings, ct, knownSources, altTitles, queryTimeout));

        // A hung provider must not hold the request open: the batch deadline aborts whatever has not
        // answered yet, and the partial answers already collected are still merged below.
        var batchTimeout = timeout ?? EnrichmentBatchTimeout;
        using var batchCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        batchCts.CancelAfter(batchTimeout);

        SourceEnrichmentResult[] results;
        try
        {
            results = await Task.WhenAll(tasks).WaitAsync(batchCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogDebug(
                "[Aggregator] Enrichment batch exceeded {Timeout}s for '{Title}'; merging the answers that arrived",
                batchTimeout.TotalSeconds,
                current.Title);
            return current with { Ratings = ratings };
        }

        var resultMap = results.ToDictionary(r => r.Source, StringComparer.OrdinalIgnoreCase);

        // Provenance: each answering source is diffed against the state before its merge, so the
        // linked-sources panel can auto-bind exactly the sources that actually contributed data,
        // together with the honest list of fields they brought in.
        var contributions = new List<SourceContributionDto>();

        foreach (var source in candidateSources)
        {
            if (!resultMap.TryGetValue(source, out var res)) continue;

            var addedRating = false;
            if (res.Rating is not null && res.Rating.Rating > 0
                && !ratings.Any(r => MediaMerger.NormalizeSourceKey(r.Source) == MediaMerger.NormalizeSourceKey(res.Rating.Source)))
            {
                ratings.Add(res.Rating);
                addedRating = true;
            }

            if (res.MatchedMedia is not null)
            {
                var before = current;
                current = MediaMerger.Merge(current, res.MatchedMedia);
                var fields = new List<string>(MediaMerger.DiffProvidedFields(before, current, res.MatchedMedia, type));
                // A rating of its own is a contribution too: the label rides on the same list so a
                // score-only source is still auto-bound with an honest "Рейтинг" entry.
                if (addedRating) fields.Add("Рейтинг");
                if (fields.Count > 0)
                {
                    contributions.Add(new SourceContributionDto(
                        res.Rating?.Source
                            ?? res.MatchedMedia.ExternalSource
                            ?? MediaMerger.GetCanonicalSourceName(source),
                        res.MatchedMedia.ExternalId,
                        res.MatchedMedia.Title,
                        fields));
                }
            }
            else if (addedRating)
            {
                // No merged payload, only a score: still a real contribution worth binding.
                var ratingOnly = res.Rating!;
                contributions.Add(new SourceContributionDto(
                    ratingOnly.Source,
                    null,
                    null,
                    ["Рейтинг"]));
            }
        }

        return current with { Ratings = ratings, SourceContributions = contributions.Count > 0 ? contributions : null };
    }

    private async Task<SourceEnrichmentResult> QuerySourceEnrichmentAsync(
        string source,
        string type,
        ExternalMediaDto current,
        List<ExternalRatingDto> existingRatings,
        CancellationToken ct,
        IReadOnlyList<LinkedSourceDto>? knownSources,
        IReadOnlyList<string>? altTitles,
        TimeSpan queryTimeout)
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
            queryCts.CancelAfter(queryTimeout);

            var sw = Stopwatch.StartNew();

            // A source already bound to this title has an id: query it directly instead of guessing
            // from a localized title, which is what failed after the display title turned Russian.
            var knownId = knownSources?
                .FirstOrDefault(known =>
                    MediaMerger.NormalizeSourceKey(known.Source) == normalizedSource
                    && !string.IsNullOrWhiteSpace(known.ExternalId))
                ?.ExternalId;

            ExternalMediaDto? fullMatch = null;
            ExternalMediaDto? match = null;

            if (!string.IsNullOrWhiteSpace(knownId))
            {
                // A bound source is queried strictly by id. Falling back to a text search here would
                // resolve a different edition — or the localized title — and overwrite the binding.
                fullMatch = await ExternalApiRetry.RunAsync(
                    async token => await provider.GetDetailsAsync(knownId, current.Title, token),
                    rateLimiter,
                    source,
                    queryCts.Token);

                if (fullMatch is null)
                {
                    return new SourceEnrichmentResult(source, null, null);
                }
            }
            else
            {
                // Foreign providers index romaji/English, not the localized Russian title. Try the
                // candidate spellings in the order that source actually searches, and keep trying
                // until one produces a strict match — a non-empty answer is not the same as a match.
                foreach (var title in SearchTitles(current, altTitles, source))
                {
                    var search = await ExternalApiRetry.RunAsync(
                        async token => await provider.SearchAsync(title, token),
                        rateLimiter,
                        source,
                        queryCts.Token);
                    if (search is null)
                    {
                        continue;
                    }

                    ExternalApiLog.Returned(logger, provider.Name, search.Count, sw.ElapsedMilliseconds);
                    match = FindStrictEnrichmentMatch(current, search, source);
                    if (match is not null)
                    {
                        break;
                    }
                }
            }

            if (fullMatch is null && match is not null)
            {
                bool shouldFetchDetails = !string.IsNullOrWhiteSpace(match.ExternalId) &&
                    (needsData || (!hasRatingFromSource && (match.Rating == null || match.Rating <= 0)));
                if (shouldFetchDetails)
                {
                    try
                    {
                        var deeper = await ExternalApiRetry.RunAsync(
                            async token => await provider.GetDetailsAsync(match.ExternalId, current.Title, token),
                            rateLimiter,
                            source,
                            queryCts.Token);
                        if (deeper is not null) fullMatch = deeper;
                    }
                    catch (Exception ex)
                    {
                        logger.LogDebug(ex, "[Aggregator] Failed deeper details from '{Source}' for '{Title}': {Message}", source, current.Title, ex.Message);
                    }
                }

                fullMatch ??= match;
            }

            if (fullMatch is null)
            {
                return new SourceEnrichmentResult(source, null, null);
            }

            ExternalRatingDto? ratingDto = null;
            if (!hasRatingFromSource)
            {
                var sourceRating = fullMatch.Ratings?.FirstOrDefault(r => MediaMerger.NormalizeSourceKey(r.Source) == normalizedSource);
                var ratingVal = sourceRating?.Rating ?? fullMatch.Rating ?? match?.Rating;
                var ratingVotes = sourceRating?.Votes ?? fullMatch.RatingVotes ?? match?.RatingVotes;

                if (ratingVal is > 0)
                {
                    ratingDto = new ExternalRatingDto
                    {
                        Source = sourceRating?.Source ?? fullMatch.ExternalSource ?? match?.ExternalSource ?? MediaMerger.GetCanonicalSourceName(source),
                        Rating = ratingVal.Value,
                        Votes = ratingVotes
                    };
                }
            }

            return new SourceEnrichmentResult(source, fullMatch, ratingDto);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, source, ex, $"enrichment '{current.Title}'");
            logger.LogDebug(ex, "[Aggregator] Enrichment query failed for source '{Source}' and title '{Title}': {Message}", source, current.Title, ex.Message);
            return new SourceEnrichmentResult(source, null, null);
        }
    }

    internal static ExternalMediaDto? FindStrictEnrichmentMatch(
        ExternalMediaDto current,
        IReadOnlyList<ExternalMediaDto> search,
        string source)
    {
        if (search.Count == 0) return null;

        var isClassicBook = MediaMerger.IsClassicBook(current);
        var isAsianSource = MediaMerger.IsAsianNovelOrMangaSource(source);

        foreach (var candidate in search)
        {
            // 1. Isolation Guard: classic books must not auto-enrich from Asian novel/manga providers
            // unless there is a 100% match on BOTH title AND author
            if (isClassicBook && isAsianSource)
            {
                if (!ImportMatchScorer.Is100PercentTitleMatch(current, candidate) ||
                    !ImportMatchScorer.AreAuthorsCompatible(current.Author, candidate.Author))
                {
                    continue;
                }
            }

            // 2. Author Guard: if both specify authors, they must match
            if (!string.IsNullOrWhiteSpace(current.Author) && !string.IsNullOrWhiteSpace(candidate.Author))
            {
                if (!ImportMatchScorer.AreAuthorsCompatible(current.Author, candidate.Author))
                {
                    continue;
                }
            }

            // 3. Year Guard: if year difference > 3 years, forbidden unless 100% title match
            if (current.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
            {
                var diff = Math.Abs(current.ReleaseYear.Value - candidate.ReleaseYear.Value);
                if (diff > 3 && !ImportMatchScorer.Is100PercentTitleMatch(current, candidate))
                {
                    continue;
                }
            }

            // 4. Title similarity Guard: no pure substring matching (>= 0.88 required)
            var similarity = ImportMatchScorer.MaxTitleSimilarity(current, candidate);
            if (similarity < 0.88)
            {
                continue;
            }

            return candidate;
        }

        return null;
    }

    /// <summary>
    /// Every spelling this title is known by, in the order the source actually indexes: a foreign
    /// provider gets romaji/English/native first, a Russian-indexing source keeps the display title
    /// first. Duplicates of the display title are skipped.
    /// </summary>
    private static IEnumerable<string> SearchTitles(
        ExternalMediaDto current,
        IReadOnlyList<string>? altTitles,
        string source)
    {
        var candidates = new List<string?> { current.Title, current.RomajiTitle, current.OriginalTitle };
        if (current.Synonyms is { Count: > 0 } synonyms) candidates.AddRange(synonyms);
        if (altTitles is { Count: > 0 }) candidates.AddRange(altTitles);

        var titles = candidates
            .Where(title => !string.IsNullOrWhiteSpace(title))
            .Select(title => title!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase);

        // AniList/Kitsu/MangaUpdates/MAL index romaji and English, so a Cyrillic display title is
        // the worst first query: trying it first was why a localized title stopped re-enriching.
        return PrefersLatin(source)
            ? titles.OrderBy(title => ContainsCyrillic(title) ? 1 : 0)
            : titles;
    }

    private static readonly HashSet<string> LatinFirstSources =
        new(StringComparer.OrdinalIgnoreCase) { "anilist", "kitsu", "mangaupdates", "mal", "myanimelist", "jikan", "mangadex" };

    private static bool PrefersLatin(string source) =>
        LatinFirstSources.Contains(MediaMerger.NormalizeSourceKey(source));

    private static bool ContainsCyrillic(string text) =>
        text.Any(c => c is >= '\u0400' and <= '\u04FF');

    /// <summary>
    /// The id is the fallback label: a details request may carry no title, and an empty query in the
    /// log is the one thing that cannot be traced back to the call that caused it.
    /// </summary>
    private static string DetailsLogLabel(string externalId, string title) =>
        !string.IsNullOrWhiteSpace(title) ? title
        : !string.IsNullOrWhiteSpace(externalId) ? $"id:{externalId}"
        : "(no id, no title)";

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderWithFallbackAsync(
        string type, string query, CancellationToken ct, bool byCreator = false)
    {
        var prioritySources = await priorityService.GetPrioritiesAsync(type, ct);
        if (prioritySources.Count == 0)
        {
            return [];
        }

        var tasks = prioritySources.Select(async source =>
        {
            ct.ThrowIfCancellationRequested();

            var provider = providerResolver.Resolve(type, source);
            if (provider is null)
            {
                return (IReadOnlyList<ExternalMediaDto>)[];
            }

            var sw = Stopwatch.StartNew();
            try
            {
                using var providerCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                providerCts.CancelAfter(SearchFallbackTimeout);
                ExternalApiLog.Querying(logger, provider.Name, type, query);
                var results = byCreator
                    ? await provider.SearchByCreatorAsync(query, providerCts.Token)
                    : await provider.SearchAsync(query, providerCts.Token);
                ExternalApiLog.Returned(logger, provider.Name, results.Count, sw.ElapsedMilliseconds);
                return results;
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex)
            {
                ExternalApiLog.Failed(logger, source, ex, $"search '{query}'");
                logger.LogDebug(ex, "[Aggregator] Search: source '{Source}' failed for '{Query}': {Message}", source, query, ex.Message);
                return [];
            }
        });

        var resultsArray = await Task.WhenAll(tasks);
        var allResults = new List<ExternalMediaDto>();
        var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var list in resultsArray)
        {
            foreach (var r in list)
            {
                var key = $"{r.ExternalSource}:{r.ExternalId}";
                if (seenIds.Add(key))
                {
                    allResults.Add(r);
                }
            }
        }

        return allResults;
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchAllAsync(string query, CancellationToken ct, bool byCreator = false)
    {
        var tasks = AllTypes.Select(type => SearchProviderSafeAsync(type, query, ct, byCreator));
        var groups = await Task.WhenAll(tasks);

        return [.. groups.SelectMany(group => group)];
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderSafeAsync(
        string type, string query, CancellationToken ct, bool byCreator = false)
    {
        try
        {
            return await SearchProviderWithFallbackAsync(type, query, ct, byCreator);
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
