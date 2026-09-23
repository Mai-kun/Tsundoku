using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Services.External;

public sealed class TmdbMetadataProvider(
    [ServiceKey] string mediaType,
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<TmdbMetadataProvider> logger) : IMetadataProvider
{
    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var apiKey = options.Value.TmdbApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            logger.LogWarning("TMDB API key is not configured, external search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient("Tmdb");
        var isMovie = mediaType == "movie";
        var searchPath = isMovie ? "search/movie" : "search/tv";

        var result = await client.GetFromJsonAsync<TmdbResponse>(
            $"{searchPath}?query={Uri.EscapeDataString(query)}&api_key={Uri.EscapeDataString(apiKey)}", ct);

        if (result?.Results is not { Count: > 0 } results)
        {
            return [];
        }

        return results
            .Where(item => isMovie ? item.Title is not null : item.Name is not null)
            .Select(item => new ExternalMediaDto
            {
                ExternalId = item.Id.ToString(),
                Title = isMovie ? item.Title! : item.Name!,
                OriginalTitle = isMovie ? item.OriginalTitle : item.OriginalName,
                CoverUrl = item.PosterPath is null ? null : $"https://image.tmdb.org/t/p/w500{item.PosterPath}",
                Description = item.Overview,
                ReleaseYear = ParseYear(isMovie ? item.ReleaseDate : item.FirstAirDate),
                Type = mediaType,
            })
            .ToList();
    }

    private static int? ParseYear(string? date) =>
        date is { Length: >= 4 } && int.TryParse(date[..4], out var year) ? year : null;

    private sealed record TmdbResponse(List<TmdbItem>? Results);

    private sealed record TmdbItem(
        long Id,
        string? Title,
        [property: JsonPropertyName("original_title")] string? OriginalTitle,
        string? Name,
        [property: JsonPropertyName("original_name")] string? OriginalName,
        string? Overview,
        [property: JsonPropertyName("poster_path")] string? PosterPath,
        [property: JsonPropertyName("release_date")] string? ReleaseDate,
        [property: JsonPropertyName("first_air_date")] string? FirstAirDate);
}
