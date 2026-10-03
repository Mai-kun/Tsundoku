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
    Task<Result<IReadOnlyList<GameRelatedItem>>> HandleAsync(
        GetExternalRelationsQuery query,
        CancellationToken ct);
}

/// <summary>
/// One endpoint behind the "load related from [source]" dropdown. Games already had their own
/// endpoints and anime/manga are queried straight from AniList by the client; films and series had
/// nothing, so this is what makes TMDb a real choice there rather than a dead entry in a list.
/// </summary>
public sealed class GetExternalRelationsHandler(
    RawgGameService gameService,
    TmdbRelationService tmdbRelations) : IGetExternalRelationsHandler
{
    public async Task<Result<IReadOnlyList<GameRelatedItem>>> HandleAsync(
        GetExternalRelationsQuery query,
        CancellationToken ct)
    {
        var wantsRecommendations = string.Equals(
            query.Kind,
            "recommendations",
            StringComparison.OrdinalIgnoreCase);

        // The source is an explicit user pick, so an unrecognised one is an empty result rather than
        // a silent substitution from some other provider.
        if (Mentions(query.Source, "rawg") || Mentions(query.Source, "steam"))
        {
            return Result<IReadOnlyList<GameRelatedItem>>.Success(
                wantsRecommendations
                    ? await gameService.GetRecommendationsAsync(
                        null, query.Title, query.Source, query.ExternalId, ct)
                    : await gameService.GetRelatedAsync(
                        null, query.Title, query.Source, query.ExternalId, ct));
        }

        if (Mentions(query.Source, "tmdb") || Mentions(query.Source, "movie database"))
        {
            var mediaType = query.Type == "movie" ? "movie" : "tv";
            return Result<IReadOnlyList<GameRelatedItem>>.Success(
                wantsRecommendations
                    ? await tmdbRelations.GetRecommendationsAsync(query.ExternalId, query.Title, mediaType, ct)
                    : await tmdbRelations.GetRelatedAsync(query.ExternalId, query.Title, mediaType, ct));
        }

        return Result<IReadOnlyList<GameRelatedItem>>.Success([]);
    }

    private static bool Mentions(string? source, string fragment) =>
        source?.Contains(fragment, StringComparison.OrdinalIgnoreCase) is true;
}