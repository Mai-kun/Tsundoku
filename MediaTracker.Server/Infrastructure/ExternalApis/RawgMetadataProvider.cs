using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed partial class RawgMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<RawgMetadataProvider> logger) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "rawg",
        Name: "RAWG Video Games Database",
        Description: "Video games metadata & ratings provider",
        MediaTypes: ["game"],
        BaseAddress: "https://api.rawg.io/api/",
        RequiresApiKey: true,
        IsDefault: true,
        Priority: 1,
        CanonicalName: "RAWG");

    [GeneratedRegex(@"store\.steampowered\.com/app/(\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex SteamAppIdRegex();

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var apiKey = options.Value.RawgApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            logger.LogWarning("RAWG API key is not configured, external search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);

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

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
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
                var client = httpClientFactory.CreateClient(Id);
                var item = await client.GetFromJsonAsync<RawgGame>(
                    $"games/{id}?key={Uri.EscapeDataString(apiKey)}", ct);

                if (item is not null)
                {
                    var steamAppId = ExtractSteamAppId(item.Stores);
                    if (steamAppId is null && HasSteamStore(item.Stores))
                    {
                        steamAppId = await TryFetchSteamAppIdAsync(client, id, apiKey, ct);
                    }

                    return MapItem(item, steamAppId);
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

    private ExternalMediaDto MapItem(RawgGame item) => MapItem(item, null);

    private ExternalMediaDto MapItem(RawgGame item, string? steamAppId)
    {
        steamAppId ??= ExtractSteamAppId(item.Stores);

        var coverUrl = !string.IsNullOrWhiteSpace(steamAppId)
            ? $"https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/{steamAppId}/library_600x900.jpg"
            : item.BackgroundImage;

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
            SteamAppId = steamAppId,
            Title = item.Name ?? string.Empty,
            OriginalTitle = item.NameOriginal,
            CoverUrl = coverUrl,
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

    private static string? ExtractSteamAppId(List<RawgGameStoreWrapper>? stores)
    {
        if (stores is null) return null;
        foreach (var entry in stores)
        {
            var url = entry.Url ?? entry.Store?.Url;
            if (!string.IsNullOrWhiteSpace(url))
            {
                var match = SteamAppIdRegex().Match(url);
                if (match.Success)
                {
                    return match.Groups[1].Value;
                }
            }
        }
        return null;
    }

    private static bool HasSteamStore(List<RawgGameStoreWrapper>? stores)
    {
        if (stores is null) return false;
        return stores.Any(s =>
            s.Store?.Id == 1 ||
            string.Equals(s.Store?.Slug, "steam", StringComparison.OrdinalIgnoreCase) ||
            s.Store?.Domain?.Contains("steampowered.com", StringComparison.OrdinalIgnoreCase) == true);
    }

    private async Task<string?> TryFetchSteamAppIdAsync(HttpClient client, long gameId, string apiKey, CancellationToken ct)
    {
        try
        {
            var storesResponse = await client.GetFromJsonAsync<RawgStoresResponse>(
                $"games/{gameId}/stores?key={Uri.EscapeDataString(apiKey)}", ct);

            if (storesResponse?.Results is { Count: > 0 } results)
            {
                foreach (var link in results)
                {
                    if (!string.IsNullOrWhiteSpace(link.Url))
                    {
                        var match = SteamAppIdRegex().Match(link.Url);
                        if (match.Success)
                        {
                            return match.Groups[1].Value;
                        }
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "Failed to fetch stores endpoint for RAWG game {GameId}", gameId);
        }

        return null;
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
        [property: JsonPropertyName("genres")] List<RawgGenre>? Genres,
        [property: JsonPropertyName("stores")] List<RawgGameStoreWrapper>? Stores);

    private sealed record RawgGameStoreWrapper(
        [property: JsonPropertyName("url")] string? Url,
        [property: JsonPropertyName("store")] RawgStoreInfo? Store);

    private sealed record RawgStoreInfo(
        [property: JsonPropertyName("id")] long? Id,
        [property: JsonPropertyName("name")] string? Name,
        [property: JsonPropertyName("slug")] string? Slug,
        [property: JsonPropertyName("domain")] string? Domain,
        [property: JsonPropertyName("url")] string? Url);

    private sealed record RawgStoresResponse(List<RawgStoreLink>? Results);

    private sealed record RawgStoreLink(
        [property: JsonPropertyName("url")] string? Url);

    private sealed record RawgGenre(string? Name);

    private sealed record RawgParentPlatform(RawgPlatform? Platform);

    private sealed record RawgPlatform(string? Name);
}
