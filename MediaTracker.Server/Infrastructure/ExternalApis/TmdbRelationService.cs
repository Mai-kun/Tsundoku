using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// TMDb's own "what to watch next" endpoints. The app had relations for games (RAWG) and for
/// anime/manga (AniList, called straight from the client) but nothing for films and series, so the
/// source dropdown on those two tabs had nothing behind it.
/// </summary>
public sealed class TmdbRelationService(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<TmdbRelationService> logger)
{
    private string ApiKey => options.Value.TmdbApiKey ?? string.Empty;

    /// <summary>Related = the title's own recommendations plus the "similar" pool, de-duplicated.</summary>
    public async Task<IReadOnlyList<GameRelatedItem>> GetRelatedAsync(
        string? externalId,
        string? title,
        string mediaType,
        CancellationToken ct)
    {
        var id = await ResolveIdAsync(externalId, title, mediaType, ct);
        if (id is null)
        {
            return [];
        }

        var pool = await FetchAsync(id, mediaType, "recommendations", ct);
        pool.AddRange(await FetchAsync(id, mediaType, "similar", ct));
        return pool
            .GroupBy(item => item.Id, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToList();
    }

    /// <summary>Recommendations are the recommendation pool only; "similar" is a different relationship.</summary>
    public Task<IReadOnlyList<GameRelatedItem>> GetRecommendationsAsync(
        string? externalId,
        string? title,
        string mediaType,
        CancellationToken ct) =>
        ResolveAndFetchAsync(externalId, title, mediaType, "recommendations", ct);

    private async Task<IReadOnlyList<GameRelatedItem>> ResolveAndFetchAsync(
        string? externalId,
        string? title,
        string mediaType,
        string path,
        CancellationToken ct)
    {
        var id = await ResolveIdAsync(externalId, title, mediaType, ct);
        return id is null ? [] : await FetchAsync(id, mediaType, path, ct);
    }

    private async Task<string?> ResolveIdAsync(
        string? externalId,
        string? title,
        string mediaType,
        CancellationToken ct)
    {
        if (long.TryParse(externalId, out var numeric))
        {
            return numeric.ToString();
        }

        if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(ApiKey))
        {
            return null;
        }

        // A TMDb caller's id only means something to TMDb, and this endpoint is also reachable from an
        // item matched by a different source, so a non-numeric id falls back to a title search.
        var searchPath = mediaType == "movie" ? "search/movie" : "search/tv";
        try
        {
            var search = await httpClientFactory
                .CreateClient(TmdbMetadataProvider.Source.Id)
                .GetFromJsonAsync<TmdbPage>(
                    $"{searchPath}?query={Uri.EscapeDataString(title)}&api_key={Uri.EscapeDataString(ApiKey)}",
                    ct);

            return search?.Results?.FirstOrDefault()?.Id?.ToString();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogDebug(ex, "TMDb relation lookup could not resolve '{Title}'", title);
            return null;
        }
    }

    private async Task<List<GameRelatedItem>> FetchAsync(
        string id,
        string mediaType,
        string path,
        CancellationToken ct)
    {
        try
        {
            var root = await httpClientFactory
                .CreateClient(TmdbMetadataProvider.Source.Id)
                .GetFromJsonAsync<TmdbPage>(
                    $"{mediaType}/{id}/{path}?api_key={Uri.EscapeDataString(ApiKey)}",
                    ct);

            return
            [
                .. (root?.Results ?? [])
                    .Select(item => (Item: item, Title: item.Title ?? item.Name))
                    .Where(entry => !string.IsNullOrWhiteSpace(entry.Title) && entry.Item.Id is not null)
                    .Select(entry => new GameRelatedItem(
                        entry.Item.Id!.Value.ToString(),
                        entry.Title!,
                        entry.Item.PosterPath is null
                            ? null
                            : $"https://image.tmdb.org/t/p/w500{entry.Item.PosterPath}",
                        entry.Item.ReleaseDate ?? entry.Item.FirstAirDate,
                        // TMDb rates 0-10, the UI shows 0-20.
                        entry.Item.VoteAverage is > 0
                            ? Math.Round(entry.Item.VoteAverage.Value * 2.0, 1)
                            : null))
            ];
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogDebug(ex, "TMDb '{Path}' failed for {MediaType}/{Id}", path, mediaType, id);
            return [];
        }
    }

    private sealed class TmdbPage
    {
        public List<TmdbRelationItem>? Results { get; set; }
    }

    private sealed class TmdbRelationItem
    {
        [JsonPropertyName("id")]
        public long? Id { get; set; }

        [JsonPropertyName("title")]
        public string? Title { get; set; }

        [JsonPropertyName("poster_path")]
        public string? PosterPath { get; set; }

        [JsonPropertyName("release_date")]
        public string? ReleaseDate { get; set; }

        [JsonPropertyName("first_air_date")]
        public string? FirstAirDate { get; set; }

        [JsonPropertyName("vote_average")]
        public double? VoteAverage { get; set; }

        /// <summary>Films spell it "title", series spell it "name"; the mapper reads whichever is set.</summary>
        public string? Name { get; set; }

    }
}
