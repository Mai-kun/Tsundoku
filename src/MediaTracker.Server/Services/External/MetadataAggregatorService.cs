using System.Text.Json;
using MediaTracker.Server.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MetadataAggregatorService(
    IServiceProvider serviceProvider,
    IMemoryCache cache)
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    public static readonly string[] AllTypes = ["anime", "manga", "movie", "tvshow", "game", "book"];

    public static readonly Dictionary<string, string[]> DefaultSourcePriority = new()
    {
        ["anime"] = ["anilist", "jikan"],
        ["manga"] = ["anilist", "mangadex", "jikan", "mangaupdates"],
        ["movie"] = ["tmdb"],
        ["tvshow"] = ["tmdb"],
        ["game"] = ["rawg"],
        ["book"] = ["openlibrary"]
    };

    public void ClearCache()
    {
        if (cache is MemoryCache memoryCache)
        {
            memoryCache.Clear();
        }
    }

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string type, string query, CancellationToken ct)
    {
        var normalizedType = NormalizeMediaType(type);
        var normalizedQuery = query.Trim();
        var cacheKey = $"{(normalizedType.Length == 0 ? "all" : normalizedType)}:{normalizedQuery.ToLowerInvariant()}";

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
        var normalizedType = NormalizeMediaType(type, source);
        ExternalMediaDto? initialDetails = null;

        if (!string.IsNullOrWhiteSpace(source))
        {
            var normalizedSource = NormalizeSourceKey(source);
            var directProvider = serviceProvider.GetKeyedService<IMetadataProvider>($"{normalizedType}:{normalizedSource}")
                                 ?? serviceProvider.GetKeyedService<IMetadataProvider>(normalizedSource)
                                 ?? serviceProvider.GetKeyedService<IMetadataProvider>(normalizedType);

            if (directProvider is not null)
            {
                try
                {
                    initialDetails = await directProvider.GetDetailsAsync(externalId, title, ct);
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    throw;
                }
                catch
                {
                    // Fall back to priority list
                }
            }
        }

        if (initialDetails is null)
        {
            var prioritySources = await GetSourcePriorityForTypeAsync(normalizedType, ct);
            foreach (var src in prioritySources)
            {
                var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{normalizedType}:{src}")
                               ?? serviceProvider.GetKeyedService<IMetadataProvider>(src)
                               ?? serviceProvider.GetKeyedService<IMetadataProvider>(normalizedType);

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
                catch
                {
                    // Try next source
                }
            }
        }

        if (initialDetails is null) return null;

        return await EnrichMultiSourceMetadataAndRatingsAsync(initialDetails, normalizedType, ct);
    }

    private async Task<ExternalMediaDto> EnrichMultiSourceMetadataAndRatingsAsync(ExternalMediaDto details, string type, CancellationToken ct)
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

        var prioritySources = await GetSourcePriorityForTypeAsync(type, ct);

        foreach (var source in prioritySources)
        {
            ct.ThrowIfCancellationRequested();
            var normalizedSource = NormalizeSourceKey(source);

            bool hasRatingFromSource = ratings.Any(r => NormalizeSourceKey(r.Source) == normalizedSource);
            bool needsData = HasMissingMetadata(current, type);

            // If we already have ratings from this source and no data is missing, we can skip
            if (hasRatingFromSource && !needsData)
            {
                continue;
            }

            var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{type}:{source}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(source);
            if (provider is null) continue;

            try
            {
                using var queryCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                queryCts.CancelAfter(TimeSpan.FromSeconds(2.5));

                var search = await provider.SearchAsync(current.Title, queryCts.Token);
                var match = search.FirstOrDefault(s => s.Title.Equals(current.Title, StringComparison.OrdinalIgnoreCase))
                            ?? search.FirstOrDefault();

                if (match is not null)
                {
                    // If match has an ID and provider can get details, try getting deeper details if still missing chapters/volumes
                    ExternalMediaDto fullMatch = match;
                    if (needsData && (match.Chapters == null || match.Volumes == null) && !string.IsNullOrWhiteSpace(match.ExternalId))
                    {
                        try
                        {
                            var deeper = await provider.GetDetailsAsync(match.ExternalId, current.Title, queryCts.Token);
                            if (deeper is not null) fullMatch = deeper;
                        }
                        catch { }
                    }

                    // Merge metadata from this source
                    current = MergeMedia(current, fullMatch);

                    // Add rating if available
                    if (!hasRatingFromSource)
                    {
                        var ratingVal = fullMatch.Rating ?? match.Rating;
                        if (ratingVal.HasValue && ratingVal.Value > 0)
                        {
                            ratings.Add(new ExternalRatingDto
                            {
                                Source = fullMatch.ExternalSource ?? match.ExternalSource ?? GetCanonicalSourceName(source),
                                Rating = ratingVal.Value,
                                Votes = fullMatch.RatingVotes ?? match.RatingVotes
                            });
                        }
                        else
                        {
                            ratings.Add(new ExternalRatingDto
                            {
                                Source = GetCanonicalSourceName(source),
                                Rating = 0,
                                Votes = null
                            });
                        }
                    }
                }
                else if (!hasRatingFromSource)
                {
                    ratings.Add(new ExternalRatingDto
                    {
                        Source = GetCanonicalSourceName(source),
                        Rating = 0,
                        Votes = null
                    });
                }
            }
            catch
            {
                if (!hasRatingFromSource)
                {
                    ratings.Add(new ExternalRatingDto
                    {
                        Source = GetCanonicalSourceName(source),
                        Rating = 0,
                        Votes = null
                    });
                }
            }
        }

        return current with { Ratings = ratings };
    }

    private static bool HasMissingMetadata(ExternalMediaDto d, string type)
    {
        if (type == "manga")
        {
            if (d.Chapters == null || d.Volumes == null || string.IsNullOrWhiteSpace(d.Author))
                return true;
        }
        else if (type is "anime" or "tvshow")
        {
            if (d.TotalCount == null || string.IsNullOrWhiteSpace(d.Studio))
                return true;
        }
        else if (type == "book")
        {
            if (d.TotalCount == null || string.IsNullOrWhiteSpace(d.Author))
                return true;
        }

        return string.IsNullOrWhiteSpace(d.Description) || d.ReleaseYear == null;
    }

    private static ExternalMediaDto MergeMedia(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        return primary with
        {
            Chapters = primary.Chapters ?? fallback.Chapters,
            Volumes = primary.Volumes ?? fallback.Volumes,
            TotalCount = primary.TotalCount ?? fallback.TotalCount ?? fallback.Chapters ?? fallback.Volumes,
            Author = !string.IsNullOrWhiteSpace(primary.Author) ? primary.Author : fallback.Author,
            Studio = !string.IsNullOrWhiteSpace(primary.Studio) ? primary.Studio : fallback.Studio,
            Description = !string.IsNullOrWhiteSpace(primary.Description) ? primary.Description : fallback.Description,
            CoverUrl = !string.IsNullOrWhiteSpace(primary.CoverUrl) ? primary.CoverUrl : fallback.CoverUrl,
            ReleaseYear = primary.ReleaseYear ?? fallback.ReleaseYear,
            ReleaseDate = !string.IsNullOrWhiteSpace(primary.ReleaseDate) ? primary.ReleaseDate : fallback.ReleaseDate,
            EndDate = !string.IsNullOrWhiteSpace(primary.EndDate) ? primary.EndDate : fallback.EndDate,
            ReleaseStatus = !string.IsNullOrWhiteSpace(primary.ReleaseStatus) ? primary.ReleaseStatus : fallback.ReleaseStatus,
            RomajiTitle = !string.IsNullOrWhiteSpace(primary.RomajiTitle) ? primary.RomajiTitle : fallback.RomajiTitle,
            OriginalTitle = !string.IsNullOrWhiteSpace(primary.OriginalTitle) ? primary.OriginalTitle : fallback.OriginalTitle,
            Platform = !string.IsNullOrWhiteSpace(primary.Platform) ? primary.Platform : fallback.Platform,
            Episodes = (primary.Episodes is { Count: > 0 } ? primary.Episodes : fallback.Episodes)
        };
    }

    private static string GetCanonicalSourceName(string source)
    {
        var lower = source.Trim().ToLowerInvariant();
        if (lower.Contains("mal") || lower.Contains("jikan") || lower.Contains("myanimelist"))
            return "MyAnimeList";
        if (lower.Contains("anilist"))
            return "AniList";
        if (lower.Contains("mangaupdates"))
            return "MangaUpdates";
        if (lower.Contains("mangadex"))
            return "MangaDex";
        if (lower.Contains("tmdb"))
            return "TMDB";
        if (lower.Contains("rawg"))
            return "RAWG";
        if (lower.Contains("openlibrary"))
            return "OpenLibrary";
        if (lower.Contains("kitsu"))
            return "Kitsu";
        return source;
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchProviderWithFallbackAsync(string type, string query, CancellationToken ct)
    {
        var prioritySources = await GetSourcePriorityForTypeAsync(type, ct);

        foreach (var source in prioritySources)
        {
            ct.ThrowIfCancellationRequested();

            var provider = serviceProvider.GetKeyedService<IMetadataProvider>($"{type}:{source}")
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(source)
                           ?? serviceProvider.GetKeyedService<IMetadataProvider>(type);

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
            catch
            {
                // Fall back to next source
            }
        }

        return [];
    }

    private async Task<IReadOnlyList<ExternalMediaDto>> SearchAllAsync(string query, CancellationToken ct)
    {
        var tasks = AllTypes.Select(type => SearchProviderSafeAsync(type, query, ct));
        var groups = await Task.WhenAll(tasks);

        return groups.SelectMany(group => group).ToList();
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
        catch
        {
            return [];
        }
    }

    private async Task<IReadOnlyList<string>> GetSourcePriorityForTypeAsync(string type, CancellationToken ct)
    {
        var defaultSources = DefaultSourcePriority.TryGetValue(type, out var def) ? def : [type];
        const string priorityCacheKey = "settings:source_priority";

        if (cache.TryGetValue(priorityCacheKey, out Dictionary<string, string[]>? cachedPriorities) && cachedPriorities is not null)
        {
            if (cachedPriorities.TryGetValue(type, out var cachedList) && cachedList.Length > 0)
            {
                return MergePriorityLists(cachedList, defaultSources);
            }
            return defaultSources;
        }

        try
        {
            using var scope = serviceProvider.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var setting = await db.Settings.AsNoTracking().FirstOrDefaultAsync(s => s.Key == "SourcePriority", ct);
            if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
            {
                var dict = JsonSerializer.Deserialize<Dictionary<string, string[]>>(setting.Value);
                if (dict is not null)
                {
                    cache.Set(priorityCacheKey, dict, TimeSpan.FromMinutes(10));
                    if (dict.TryGetValue(type, out var list) && list.Length > 0)
                    {
                        return MergePriorityLists(list, defaultSources);
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // fallback
        }

        return defaultSources;
    }

    private static IReadOnlyList<string> MergePriorityLists(string[] userList, string[] defaultSources)
    {
        var merged = userList.Where(s => defaultSources.Contains(s, StringComparer.OrdinalIgnoreCase)).ToList();
        foreach (var s in defaultSources)
        {
            if (!merged.Contains(s, StringComparer.OrdinalIgnoreCase))
            {
                merged.Add(s);
            }
        }
        return merged;
    }

    private static string NormalizeMediaType(string type, string? source = null)
    {
        var lowerType = type?.Trim().ToLowerInvariant() ?? "";
        if (!string.IsNullOrWhiteSpace(source))
        {
            var lowerSource = source.Trim().ToLowerInvariant();
            if (lowerSource.Contains("mangaupdates") || lowerSource.Contains("mangadex"))
            {
                return "manga";
            }
            if (lowerSource.Contains("anilist") || lowerSource.Contains("jikan") || lowerSource.Contains("mal") || lowerSource.Contains("shikimori"))
            {
                if (lowerType is "tvshow" or "movie" or "all" or "")
                {
                    return "anime";
                }
            }
        }
        return lowerType;
    }

    private static string NormalizeSourceKey(string source)
    {
        var lower = source.Trim().ToLowerInvariant();
        if (lower.Contains("mal") || lower.Contains("myanimelist") || lower.Contains("jikan"))
            return "jikan";
        if (lower.Contains("mangaupdates"))
            return "mangaupdates";
        if (lower.Contains("mangadex"))
            return "mangadex";
        if (lower.Contains("anilist"))
            return "anilist";
        if (lower.Contains("tmdb") || lower.Contains("movie database"))
            return "tmdb";
        if (lower.Contains("rawg"))
            return "rawg";
        if (lower.Contains("openlibrary"))
            return "openlibrary";
        return lower;
    }
}
