using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.External.GetExternalRelations;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.GetRecommendations;

public sealed record GetRecommendationsCommand(
    Guid MediaId,
    string? Source,
    bool ForceRefresh = false);

public interface IGetRecommendationsHandler
{
    Task<Result<IReadOnlyList<ExternalRecommendationDto>>> HandleAsync(
        GetRecommendationsCommand command,
        CancellationToken ct);
}

/// <summary>
/// Loads recommendations for one item and keeps them on the row.
///
/// The list used to be fetched by the browser and posted back as a blob the detail screen then parsed,
/// so it lived in a localStorage cache and in whatever the provider happened to return at the time. It
/// now lives next to the item it describes: a fresh copy is served straight out of SQLite, so reloading
/// the page costs no request and the tab is already populated when it opens.
/// </summary>
public sealed class GetRecommendationsHandler(
    AppDbContext db,
    IGetExternalRelationsHandler relations,
    TmdbRelationService tmdbRelations) : IGetRecommendationsHandler
{
    public async Task<Result<IReadOnlyList<ExternalRecommendationDto>>> HandleAsync(
        GetRecommendationsCommand command,
        CancellationToken ct)
    {
        var item = await MediaItemGraph
            .LoadTracked(db)
            .SingleOrDefaultAsync(media => media.Id == command.MediaId, ct);

        if (item is null)
        {
            return Result<IReadOnlyList<ExternalRecommendationDto>>.Failure(
                Error.NotFound($"Media item '{command.MediaId}' was not found."));
        }

        var now = DateTime.UtcNow;

        // The whole point of the cache: a copy younger than the lifetime is authoritative, so the
        // provider is not asked again. ForceRefresh is the "reload" button on the panel.
        if (!command.ForceRefresh && item.HasFreshRecommendations(now))
        {
            return Result<IReadOnlyList<ExternalRecommendationDto>>.Success(
                MediaJsonCache.Deserialize<ExternalRecommendationDto>(item.RecommendationsJson));
        }

        var mediaType = ResolveMediaType(item);
        var recommendations = await FetchAsync(item, command.Source, mediaType, ct);

        // An empty result is stored too. Without the timestamp it would leave the row looking never
        // fetched, and every later open would re-ask a source that has nothing to give.
        item.CacheRecommendations(MediaJsonCache.Serialize(recommendations), now);
        await db.SaveChangesAsync(ct);

        return Result<IReadOnlyList<ExternalRecommendationDto>>.Success(recommendations);
    }

    /// <summary>
    /// Which provider family answers this item. There is no anime entity type in this model: an anime is
    /// a Movie or TvShow flagged <c>IsAnime</c>, so the raw type alone would send every anime to TMDb and
    /// leave AniList unreachable for the one source that is actually best at it. This mirrors the bucket
    /// the client derives when it lists the sources for an item.
    /// </summary>
    private static string ResolveMediaType(MediaItem item) =>
        item is Movie { IsAnime: true } or TvShow { IsAnime: true }
            ? "anime"
            : MediaResponseMapper.GetType(item);

    private async Task<IReadOnlyList<ExternalRecommendationDto>> FetchAsync(
        MediaItem item,
        string? source,
        string mediaType,
        CancellationToken ct)
    {
        // anime/manga go to AniList and films/series to TMDb, the same split the Related tab uses;
        // games have no AniList/TMDb equivalent and are answered by the relations handler's RAWG branch.
        if (mediaType is "anime" or "manga")
        {
            var result = await relations.HandleAsync(
                new GetExternalRelationsQuery(
                    mediaType,
                    item.ExternalId,
                    item.Title,
                    source,
                    "recommendations"),
                ct);

            return result.TryGetValue(out var found)
                ? [.. found.Select(ToRecommendation)]
                : [];
        }

        if (mediaType is "movie" or "tvshow")
        {
            var items = await tmdbRelations.GetRecommendationsAsync(
                item.ExternalId,
                item.Title,
                mediaType == "movie" ? "movie" : "tv",
                ct);

            return [.. items.Select(item => new ExternalRecommendationDto(
                item.Id,
                item.Title,
                item.CoverUrl,
                item.Score,
                "TMDb"))];
        }

        var games = await relations.HandleAsync(
            new GetExternalRelationsQuery(mediaType, item.ExternalId, item.Title, source, "recommendations"),
            ct);

        return games.TryGetValue(out var foundGames)
            ? [.. foundGames.Select(ToRecommendation)]
            : [];
    }

    private static ExternalRecommendationDto ToRecommendation(ExternalRelationDto relation) =>
        new(
            relation.Media.ExternalId,
            relation.Media.Title,
            relation.Media.CoverUrl,
            relation.Media.Rating,
            relation.Media.ExternalSource ?? "");
}