using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.External.GetExternalRelations;

public sealed record GetExternalRelationsQuery(
    string? Type,
    string? ExternalId,
    string? Title,
    string? Source,
    string? Kind);

public interface IGetExternalRelationsHandler
{
    Task<Result<IReadOnlyList<ExternalRelationDto>>> HandleAsync(
        GetExternalRelationsQuery query,
        CancellationToken ct);
}

/// <summary>
/// One endpoint behind the "load related from [source]" dropdown. Games go to RAWG, films and series
/// to TMDb, and anime/manga to AniList — the last of which used to be called straight from the browser,
/// which put the AniList wire shape in the client and left the Related tab the one screen that paid for
/// a network round trip the server could have made. Every source answers in the same shape so the tab
/// maps one type instead of one per provider.
/// </summary>
public sealed class GetExternalRelationsHandler(
    RawgGameService gameService,
    TmdbRelationService tmdbRelations,
    IMetadataProviderResolver providerResolver,
    IMemoryCache cache) : IGetExternalRelationsHandler
{
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(10);

    public async Task<Result<IReadOnlyList<ExternalRelationDto>>> HandleAsync(
        GetExternalRelationsQuery query,
        CancellationToken ct)
    {
        var wantsRecommendations = string.Equals(
            query.Kind,
            "recommendations",
            StringComparison.OrdinalIgnoreCase);

        // Relations/recommendations are pure upstream reads: a 10-minute cache keeps re-opening the
        // Related tab (and duplicated panel fetches) from re-paying the AniList rate limit.
        var cacheKey = $"ext-relations:{(wantsRecommendations ? "recs" : "rel")}:{query.Type?.ToLowerInvariant()}:{query.Source?.ToLowerInvariant()}:{query.ExternalId}:{query.Title?.ToLowerInvariant()}";
        if (cache.TryGetValue(cacheKey, out IReadOnlyList<ExternalRelationDto>? cached) && cached is not null)
        {
            return Result<IReadOnlyList<ExternalRelationDto>>.Success(cached);
        }

        var result = await FetchUncachedAsync(query, wantsRecommendations, ct);
        cache.Set(cacheKey, result, CacheDuration);
        return Result<IReadOnlyList<ExternalRelationDto>>.Success(result);
    }

    private async Task<IReadOnlyList<ExternalRelationDto>> FetchUncachedAsync(
        GetExternalRelationsQuery query, bool wantsRecommendations, CancellationToken ct)
    {
        // MangaDex has to be caught before the AniList branch below: for a manga it would otherwise
        // swallow the pick and look a MangaDex uuid up on AniList, where it matches nothing.
        // Recommendations stay with AniList — MangaDex has no recommendations endpoint, and the
        // relations list is not a recommendation feed.
        if (!wantsRecommendations && Mentions(query.Source, MangaDexMetadataProvider.Source.Id))
        {
            if (providerResolver.Resolve(query.Type ?? "manga", MangaDexMetadataProvider.Source.Id)
                is not MangaDexMetadataProvider mangaDex)
            {
                return [];
            }

            var relations = await mangaDex.GetRelationsAsync(
                query.ExternalId, ct, query.Title);

            return [.. relations];
        }

        var isAnimeOrManga = query.Type is "anime" or "manga"
            || Mentions(query.Source, "anilist")
            || Mentions(query.Source, "shikimori")
            || Mentions(query.Source, "kitsu");

        // The frontend sends the bucket it used to pick sources from, so a film flagged as anime lands
        // on AniList exactly like it did when the browser issued the query itself.
        if (isAnimeOrManga && !Mentions(query.Source, MangaDexMetadataProvider.Source.Id))
        {
            var resolvedType = query.Type is "manga" ? "manga" : "anime";
            if (providerResolver.Resolve(resolvedType, AniListMetadataProvider.Source.Id)
                is not AniListMetadataProvider aniList)
            {
                return [];
            }

            // Every anime/manga source in the dropdown stores someone else's id: Shikimori stores
            // MyAnimeList ids, so only a literal AniList pick is an AniList id. A MAL-shaped id sent
            // as an AniList id silently matches the wrong title.
            var idIsMal = !Mentions(query.Source, AniListMetadataProvider.Source.Id);

            if (wantsRecommendations)
            {
                var recommendations = await aniList.GetRecommendationsAsync(
                    query.ExternalId, idIsMal, query.Title, ct);

                return [.. recommendations.Select(ToRelation)];
            }

            return await aniList.GetRelationsAsync(query.ExternalId, idIsMal, query.Title, ct);
        }

        // The source is an explicit user pick, so an unrecognised one is an empty result rather than
        // a silent substitution from some other provider.
        if (Mentions(query.Source, "rawg") || Mentions(query.Source, "steam"))
        {
            var items = wantsRecommendations
                ? await gameService.GetRecommendationsAsync(
                    null, query.Title, query.Source, query.ExternalId, ct)
                : await gameService.GetRelatedAsync(
                    null, query.Title, query.Source, query.ExternalId, ct);

            return [.. items.Select(item => ToRelation(item, "OTHER", "game", query.Source))];
        }

        if (Mentions(query.Source, "tmdb") || Mentions(query.Source, "movie database"))
        {
            var mediaType = query.Type == "movie" ? "movie" : "tv";
            var items = wantsRecommendations
                ? await tmdbRelations.GetRecommendationsAsync(query.ExternalId, query.Title, mediaType, ct)
                : await tmdbRelations.GetRelatedAsync(query.ExternalId, query.Title, mediaType, ct);

            return [.. items.Select(item => ToRelation(item, "SIMILAR", mediaType, query.Source))];
        }

        return [];
    }

    /// <summary>
    /// RAWG and TMDb only report an id, a title and a poster. That is not a deficiency to paper over
    /// here: the fields the tab cannot fill stay null and the tab already tolerates that.
    /// </summary>
    /// <summary>
    /// AniList's recommendation list and its relation list describe the same kind of row, so a
    /// recommendation is lifted into the shared relation shape rather than adding a second shape the
    /// client has to special-case.
    /// </summary>
    private static ExternalRelationDto ToRelation(ExternalRecommendationDto recommendation) =>
        new(
            "OTHER",
            new ExternalMediaDto
            {
                ExternalId = recommendation.Id,
                Title = recommendation.Title,
                CoverUrl = recommendation.CoverUrl,
                Rating = recommendation.Rating,
                Type = "anime",
                ExternalSource = recommendation.Source,
            });

    private static ExternalRelationDto ToRelation(
        GameRelatedItem item,
        string relationType,
        string type,
        string? source) =>
        new(relationType, new ExternalMediaDto
        {
            ExternalId = item.Id,
            Title = item.Title,
            CoverUrl = item.CoverUrl,
            ReleaseDate = item.ReleaseDate,
            Rating = item.Score,
            Type = type,
            ExternalSource = source,
        });

    private static bool Mentions(string? source, string fragment) =>
        source?.Contains(fragment, StringComparison.OrdinalIgnoreCase) is true;
}