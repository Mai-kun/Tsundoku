using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.ExternalApis;

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
    IMetadataProviderResolver providerResolver) : IGetExternalRelationsHandler
{
    public async Task<Result<IReadOnlyList<ExternalRelationDto>>> HandleAsync(
        GetExternalRelationsQuery query,
        CancellationToken ct)
    {
        var wantsRecommendations = string.Equals(
            query.Kind,
            "recommendations",
            StringComparison.OrdinalIgnoreCase);

        // MangaDex has to be caught before the AniList branch below: for a manga it would otherwise
        // swallow the pick and look a MangaDex uuid up on AniList, where it matches nothing.
        // Recommendations stay with AniList — MangaDex has no recommendations endpoint, and the
        // relations list is not a recommendation feed.
        if (!wantsRecommendations && Mentions(query.Source, MangaDexMetadataProvider.Source.Id))
        {
            if (providerResolver.Resolve(query.Type ?? "manga", MangaDexMetadataProvider.Source.Id)
                is not MangaDexMetadataProvider mangaDex)
            {
                return Result<IReadOnlyList<ExternalRelationDto>>.Success([]);
            }

            var relations = await mangaDex.GetRelationsAsync(
                query.ExternalId, ct, query.Title);

            return Result<IReadOnlyList<ExternalRelationDto>>.Success([.. relations]);
        }

        // The frontend sends the bucket it used to pick sources from, so a film flagged as anime lands
        // on AniList exactly like it did when the browser issued the query itself.
        if (query.Type is "anime" or "manga")
        {
            if (providerResolver.Resolve(query.Type, AniListMetadataProvider.Source.Id)
                is not AniListMetadataProvider aniList)
            {
                return Result<IReadOnlyList<ExternalRelationDto>>.Success([]);
            }

            // Every anime/manga source in the dropdown is AniList looked up by a different id: MAL,
            // Jikan and Shikimori all store MyAnimeList ids, so only a literal AniList pick is an
            // AniList id. A MAL-shaped id sent as an AniList id silently matches the wrong title.
            var idIsMal = !Mentions(query.Source, AniListMetadataProvider.Source.Id);

            if (wantsRecommendations)
            {
                var recommendations = await aniList.GetRecommendationsAsync(
                    query.ExternalId, idIsMal, query.Title, ct);

                return Result<IReadOnlyList<ExternalRelationDto>>.Success(
                    [.. recommendations.Select(ToRelation)]);
            }

            return Result<IReadOnlyList<ExternalRelationDto>>.Success(
                await aniList.GetRelationsAsync(query.ExternalId, idIsMal, query.Title, ct));
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

            return Result<IReadOnlyList<ExternalRelationDto>>.Success(
                [.. items.Select(item => ToRelation(item, "OTHER", "game", query.Source))]);
        }

        if (Mentions(query.Source, "tmdb") || Mentions(query.Source, "movie database"))
        {
            var mediaType = query.Type == "movie" ? "movie" : "tv";
            var items = wantsRecommendations
                ? await tmdbRelations.GetRecommendationsAsync(query.ExternalId, query.Title, mediaType, ct)
                : await tmdbRelations.GetRelatedAsync(query.ExternalId, query.Title, mediaType, ct);

            return Result<IReadOnlyList<ExternalRelationDto>>.Success(
                [.. items.Select(item => ToRelation(item, "SIMILAR", mediaType, query.Source))]);
        }

        return Result<IReadOnlyList<ExternalRelationDto>>.Success([]);
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