using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Services.External;

public sealed class TmdbMetadataProvider(
    [ServiceKey] string? serviceKey = null,
    IHttpClientFactory httpClientFactory = null!,
    IOptions<ExternalApiOptions> options = null!,
    ILogger<TmdbMetadataProvider> logger = null!) : IMetadataProvider
{
    public string Id => "tmdb";
    public string Name => "The Movie Database (TMDb)";
    public string Description => "Movies and TV Shows metadata & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["movie", "tvshow"];
    public bool RequiresApiKey => true;
    public bool IsDefault => true;

    private readonly string mediaType = serviceKey?.StartsWith("movie", StringComparison.OrdinalIgnoreCase) == true ? "movie" : "tvshow";

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
            .Select(MapItem)
            .ToList();
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var apiKey = options.Value.TmdbApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return null;
        }

        if (long.TryParse(externalId, out var id))
        {
            try
            {
                var client = httpClientFactory.CreateClient("Tmdb");
                var isMovie = mediaType == "movie";
                var detailPath = isMovie ? $"movie/{id}" : $"tv/{id}";
                var item = await client.GetFromJsonAsync<TmdbItem>(
                    $"{detailPath}?api_key={Uri.EscapeDataString(apiKey)}", ct);

                if (item is not null)
                {
                    return MapItem(item);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to get TMDB details for {Id}", externalId);
            }
        }

        var searchResults = await SearchAsync(title, ct);
        return searchResults.FirstOrDefault();
    }

    private ExternalMediaDto MapItem(TmdbItem item)
    {
        var isMovie = mediaType == "movie";
        var rating = item.VoteAverage is { } va && va > 0 ? Math.Round(va, 1) : (double?)null;
        var ratings = rating is not null
            ? new List<ExternalRatingDto>
            {
                new() { Source = "TMDB", Rating = rating.Value, Votes = item.VoteCount }
            }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            ExternalSource = "TMDB",
            Title = isMovie ? item.Title ?? string.Empty : item.Name ?? string.Empty,
            OriginalTitle = isMovie ? item.OriginalTitle : item.OriginalName,
            CoverUrl = item.PosterPath is null ? null : $"https://image.tmdb.org/t/p/w500{item.PosterPath}",
            Description = item.Overview,
            ReleaseYear = ParseYear(isMovie ? item.ReleaseDate : item.FirstAirDate),
            ReleaseDate = isMovie ? item.ReleaseDate : item.FirstAirDate,
            ReleaseStatus = item.Status,
            RuntimeMinutes = isMovie ? item.Runtime : null,
            Type = mediaType,
            Rating = rating,
            RatingVotes = item.VoteCount,
            Ratings = ratings,
            TotalCount = isMovie ? item.Runtime : item.NumberOfEpisodes
        };
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
        [property: JsonPropertyName("first_air_date")] string? FirstAirDate,
        [property: JsonPropertyName("vote_average")] double? VoteAverage,
        [property: JsonPropertyName("vote_count")] int? VoteCount,
        [property: JsonPropertyName("runtime")] int? Runtime,
        [property: JsonPropertyName("number_of_episodes")] int? NumberOfEpisodes,
        [property: JsonPropertyName("status")] string? Status);
}
