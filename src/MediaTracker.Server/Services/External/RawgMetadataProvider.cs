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
    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var apiKey = options.Value.RawgApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            logger.LogWarning("RAWG API key is not configured, external search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient("Rawg");

        var result = await client.GetFromJsonAsync<RawgResponse>(
            $"games?search={Uri.EscapeDataString(query)}&key={Uri.EscapeDataString(apiKey)}&page_size=10", ct);

        if (result?.Results is not { Count: > 0 } results)
        {
            return [];
        }

        return results.Select(item => new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            Title = item.Name ?? string.Empty,
            OriginalTitle = item.NameOriginal,
            CoverUrl = item.BackgroundImage,
            ReleaseYear = ParseYear(item.Released),
            Type = "game",
            Platform = JoinPlatforms(item.ParentPlatforms),
        }).ToList();
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
        [property: JsonPropertyName("background_image")] string? BackgroundImage,
        [property: JsonPropertyName("parent_platforms")] List<RawgParentPlatform>? ParentPlatforms);

    private sealed record RawgParentPlatform(RawgPlatform? Platform);

    private sealed record RawgPlatform(string? Name);
}
