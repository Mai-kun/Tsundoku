using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Services.External;

public sealed class RawgMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<RawgMetadataProvider> logger) : IMetadataProvider
{
    public string Id => "rawg";
    public string Name => "RAWG Video Games Database";
    public string Description => "Video games metadata & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["game"];
    public bool RequiresApiKey => true;
    public bool IsDefault => true;

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var apiKey = options.Value.RawgApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            logger.LogWarning("RAWG API key is not configured, external search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient("Rawg");

        try
        {
            var result = await client.GetFromJsonAsync<RawgResponse>(
                $"games?search={Uri.EscapeDataString(query)}&key={Uri.EscapeDataString(apiKey)}&page_size=10", ct);

            if (result?.Results is not { Count: > 0 } results)
            {
                return [];
            }

            return results.ConvertAll(MapItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to search RAWG for {Query}", query);
            throw;
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var apiKey = options.Value.RawgApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return null;
        }

        if (long.TryParse(externalId, out var id))
        {
            try
            {
                var client = httpClientFactory.CreateClient("Rawg");
                var item = await client.GetFromJsonAsync<RawgGame>(
                    $"games/{id}?key={Uri.EscapeDataString(apiKey)}", ct);

                if (item is not null)
                {
                    return MapItem(item);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to get RAWG details for {Id}", externalId);
                throw;
            }
        }

        var searchResults = await SearchAsync(title, ct);
        return searchResults.Count > 0 ? searchResults[0] : null;
    }

    private ExternalMediaDto MapItem(RawgGame item)
    {
        var rating = item.Rating is { } r && r > 0 ? Math.Round(r * 2.0, 1) : (double?)null;
        var ratings = rating is not null
            ? new List<ExternalRatingDto>
            {
                new() { Source = "RAWG", Rating = rating.Value, Votes = item.RatingsCount }
            }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            ExternalSource = "RAWG",
            Title = item.Name ?? string.Empty,
            OriginalTitle = item.NameOriginal,
            CoverUrl = item.BackgroundImage,
            Description = item.DescriptionRaw ?? item.Description,
            ReleaseYear = ParseYear(item.Released),
            ReleaseDate = item.Released,
            ReleaseStatus = DetermineStatus(item.Tba, item.Released, item.Genres),
            Genres = item.Genres?.Select(g => g.Name).Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n!).ToList(),
            Type = "game",
            Platform = JoinPlatforms(item.ParentPlatforms),
            Rating = rating,
            RatingVotes = item.RatingsCount,
            Ratings = ratings
        };
    }

    private static string DetermineStatus(bool? tba, string? released, List<RawgGenre>? genres)
    {
        if (tba == true) return "Coming Soon";
        if (DateTime.TryParse(released, out var parsedDate) && parsedDate > DateTime.UtcNow) return "Coming Soon";
        if (genres?.Any(g => g.Name?.Contains("Early Access", StringComparison.OrdinalIgnoreCase) == true) == true)
            return "Early Access";
        return "Full Release";
    }

    private static int? ParseYear(string? date) =>
        date is { Length: >= 4 } && int.TryParse(date[..4], out var year) ? year : null;

    private static string? JoinPlatforms(List<RawgParentPlatform>? platforms)
    {
        var names = platforms?.Select(platform => platform.Platform?.Name).Where(name => name is not null).ToList();
        return names is { Count: > 0 } ? string.Join(", ", names) : null;
    }

    private sealed record RawgResponse(List<RawgGame>? Results);

    private sealed record RawgGame(
        long Id,
        string? Name,
        [property: JsonPropertyName("name_original")] string? NameOriginal,
        string? Released,
        bool? Tba,
        [property: JsonPropertyName("background_image")] string? BackgroundImage,
        [property: JsonPropertyName("description_raw")] string? DescriptionRaw,
        string? Description,
        double? Rating,
        [property: JsonPropertyName("ratings_count")] int? RatingsCount,
        [property: JsonPropertyName("parent_platforms")] List<RawgParentPlatform>? ParentPlatforms,
        [property: JsonPropertyName("genres")] List<RawgGenre>? Genres);

    private sealed record RawgGenre(string? Name);

    private sealed record RawgParentPlatform(RawgPlatform? Platform);

    private sealed record RawgPlatform(string? Name);
}
