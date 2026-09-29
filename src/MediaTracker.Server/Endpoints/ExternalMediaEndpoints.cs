using MediaTracker.Server.Services.External;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Endpoints;

public static class ExternalMediaEndpoints
{
    private static readonly string[] SupportedTypes = ["all", "game", "movie", "tvshow", "anime", "manga", "book"];

    public static IEndpointRouteBuilder MapExternalMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/external");

        group.MapGet("/search", SearchExternalMedia);
        group.MapGet("/details", GetExternalMediaDetails);
        group.MapPost("/translate", TranslateText);
        group.MapGet("/games/achievements", GetGameAchievements);
        group.MapGet("/games/related", GetGameRelated);
        group.MapGet("/games/recommendations", GetGameRecommendations);

        return app;
    }

    private static async Task<IResult> GetExternalMediaDetails(
        string? type,
        string? id,
        string? title,
        string? source,
        MetadataAggregatorService aggregator,
        CancellationToken ct)
    {
        var normalizedType = string.IsNullOrWhiteSpace(type) ? "anime" : type.Trim().ToLowerInvariant();
        var normalizedId = id?.Trim() ?? string.Empty;
        var normalizedTitle = title?.Trim() ?? string.Empty;

        if (string.IsNullOrWhiteSpace(normalizedId) && string.IsNullOrWhiteSpace(normalizedTitle))
        {
            return Results.BadRequest(new { message = "Either id or title is required." });
        }

        var details = await aggregator.GetDetailsAsync(normalizedType, normalizedId, normalizedTitle, ct, source);
        return details is not null ? Results.Ok(details) : Results.NotFound();
    }

    private static async Task<IResult> SearchExternalMedia(
        string? type,
        string? query,
        MetadataAggregatorService aggregator,
        CancellationToken ct)
    {
        var normalizedType = string.IsNullOrWhiteSpace(type) ? "all" : type.Trim().ToLowerInvariant();
        var normalizedQuery = query?.Trim() ?? string.Empty;

        var errors = new Dictionary<string, string[]>();

        if (!SupportedTypes.Contains(normalizedType))
        {
            errors["type"] = [$"Type must be one of: {string.Join(", ", SupportedTypes)}."];
        }

        if (normalizedQuery.Length < 2)
        {
            errors["query"] = ["Query must contain at least 2 characters."];
        }

        if (errors.Count > 0)
        {
            return Results.ValidationProblem(errors);
        }

        var results = await aggregator.SearchAsync(normalizedType, normalizedQuery, ct);
        return Results.Ok(results);
    }

    private static async Task<IResult> TranslateText(
        TranslateRequest request,
        ITranslationService translationService,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
        {
            return Results.BadRequest(new { message = "Text is required." });
        }

        var translated = await translationService.TranslateAsync(request.Text, request.TargetLanguage ?? "ru", ct);
        return Results.Ok(new TranslateResponse(translated));
    }

    private static async Task<IResult> GetGameAchievements(
        string? steamAppId,
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        IHttpClientFactory httpClientFactory,
        Microsoft.Extensions.Options.IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient();

        // 1. Steam First
        try
        {
            var appId = steamAppId;
            if (string.IsNullOrWhiteSpace(appId) && string.Equals(externalSource, "steam", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(externalId))
            {
                appId = externalId;
            }

            if (string.IsNullOrWhiteSpace(appId) && !string.IsNullOrWhiteSpace(title))
            {
                var search = await client.GetFromJsonAsync<SteamSearchRoot>($"https://store.steampowered.com/api/storesearch/?term={Uri.EscapeDataString(title)}&l=english&cc=US", ct);
                if (search?.Items is { Count: > 0 })
                {
                    appId = search.Items[0].Id.ToString();
                }
            }

            if (!string.IsNullOrWhiteSpace(appId))
            {
                var details = await client.GetFromJsonAsync<Dictionary<string, SteamAppDetailsRoot>>($"https://store.steampowered.com/api/appdetails?appids={Uri.EscapeDataString(appId)}&l=english", ct);
                if (details is not null && details.TryGetValue(appId, out var wrapper) && wrapper.Data?.Achievements is { Total: > 0 } ach)
                {
                    var items = (ach.Highlighted ?? [])
                        .Select(h => new GameAchievementItem(h.LocalizedName ?? h.Name ?? "Achievement", null, h.Path))
                        .ToList();
                    return Results.Ok(new GameAchievementsResponse(ach.Total, items));
                }
            }
        }
        catch
        {
            // Steam failed, fall back to RAWG
        }

        // 2. RAWG Fallback
        var rawgKey = options.Value.RawgApiKey;
        if (!string.IsNullOrWhiteSpace(rawgKey))
        {
            try
            {
                var rId = rawgId;
                if (string.IsNullOrWhiteSpace(rId) && string.Equals(externalSource, "rawg", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(externalId))
                {
                    rId = externalId;
                }

                if (string.IsNullOrWhiteSpace(rId) && !string.IsNullOrWhiteSpace(title))
                {
                    var rawgSearch = await client.GetFromJsonAsync<RawgSearchRoot>($"https://api.rawg.io/api/games?search={Uri.EscapeDataString(title)}&key={Uri.EscapeDataString(rawgKey)}&page_size=1", ct);
                    if (rawgSearch?.Results is { Count: > 0 })
                    {
                        rId = rawgSearch.Results[0].Id.ToString();
                    }
                }

                if (!string.IsNullOrWhiteSpace(rId))
                {
                    var achRes = await client.GetFromJsonAsync<RawgAchievementsRoot>($"https://api.rawg.io/api/games/{rId}/achievements?key={Uri.EscapeDataString(rawgKey)}&page_size=20", ct);
                    if (achRes is not null && achRes.Count > 0)
                    {
                        var items = (achRes.Results ?? [])
                            .Select(r => new GameAchievementItem(r.Name ?? "Achievement", r.Description, r.Image))
                            .ToList();
                        return Results.Ok(new GameAchievementsResponse(achRes.Count, items));
                    }
                }
            }
            catch
            {
                // RAWG fallback failed
            }
        }

        return Results.Ok(new GameAchievementsResponse(0, []));
    }

    private static async Task<IResult> GetGameRelated(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        IHttpClientFactory httpClientFactory,
        Microsoft.Extensions.Options.IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var rawgKey = options.Value.RawgApiKey;
        if (string.IsNullOrWhiteSpace(rawgKey))
        {
            return Results.Ok(Array.Empty<GameRelatedItem>());
        }

        var client = httpClientFactory.CreateClient();
        try
        {
            var rId = rawgId;
            if (string.IsNullOrWhiteSpace(rId) && string.Equals(externalSource, "rawg", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(externalId))
            {
                rId = externalId;
            }

            if (string.IsNullOrWhiteSpace(rId) && !string.IsNullOrWhiteSpace(title))
            {
                var rawgSearch = await client.GetFromJsonAsync<RawgSearchRoot>($"https://api.rawg.io/api/games?search={Uri.EscapeDataString(title)}&key={Uri.EscapeDataString(rawgKey)}&page_size=1", ct);
                if (rawgSearch?.Results is { Count: > 0 })
                {
                    rId = rawgSearch.Results[0].Id.ToString();
                }
            }

            if (!string.IsNullOrWhiteSpace(rId))
            {
                var series = await client.GetFromJsonAsync<RawgSeriesRoot>($"https://api.rawg.io/api/games/{rId}/game-series?key={Uri.EscapeDataString(rawgKey)}&page_size=20", ct);
                if (series?.Results is { Count: > 0 } list)
                {
                    var seenNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    if (!string.IsNullOrWhiteSpace(title)) seenNames.Add(title.Trim());
                    if (!string.IsNullOrWhiteSpace(rId)) seenIds.Add(rId.Trim());

                    var results = new List<GameRelatedItem>();
                    foreach (var g in list)
                    {
                        var gid = g.Id.ToString();
                        var gname = (g.Name ?? string.Empty).Trim();
                        if (string.IsNullOrWhiteSpace(gname)) continue;
                        if (!seenIds.Add(gid) || !seenNames.Add(gname)) continue;

                        results.Add(new GameRelatedItem(
                            gid,
                            gname,
                            g.BackgroundImage,
                            g.Released,
                            g.Rating is > 0 ? Math.Round(g.Rating.Value * 2.0, 1) : null
                        ));
                    }
                    return Results.Ok(results);
                }
            }
        }
        catch
        {
            // Fallback gracefully
        }

        return Results.Ok(Array.Empty<GameRelatedItem>());
    }

    private static async Task<IResult> GetGameRecommendations(
        string? query,
        IHttpClientFactory httpClientFactory,
        Microsoft.Extensions.Options.IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient();
        var key = options.Value.TasteDiveApiKey;

        if (!string.IsNullOrWhiteSpace(key) && !string.IsNullOrWhiteSpace(query))
        {
            try
            {
                var res = await client.GetFromJsonAsync<TasteDiveRoot>($"https://tastedive.com/api/similar?q={Uri.EscapeDataString(query)}&type=game&k={Uri.EscapeDataString(key)}&info=1", ct);
                if (res?.Similar?.Results is { Count: > 0 } recs)
                {
                    var items = recs.Select(r => new GameRecommendationItem(r.Name, r.WTeaser, r.YUrl)).ToList();
                    return Results.Ok(items);
                }
            }
            catch
            {
                // TasteDive failed
            }
        }

        return Results.Ok(Array.Empty<GameRecommendationItem>());
    }
}

public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
public sealed record TranslateResponse(string TranslatedText);

public sealed record GameAchievementItem(string Name, string? Description, string? IconUrl);
public sealed record GameAchievementsResponse(int TotalCount, IReadOnlyList<GameAchievementItem> Achievements);

public sealed record GameRelatedItem(string Id, string Title, string? CoverUrl, string? ReleaseDate, double? Score);
public sealed record GameRecommendationItem(string Name, string? Description, string? Url);

file sealed class SteamSearchRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("items")]
    public List<SteamSearchItem>? Items { get; set; }
}

file sealed class SteamSearchItem
{
    [System.Text.Json.Serialization.JsonPropertyName("id")]
    public long Id { get; set; }
}

file sealed class SteamAppDetailsRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("data")]
    public SteamAppDetailsData? Data { get; set; }
}

file sealed class SteamAppDetailsData
{
    [System.Text.Json.Serialization.JsonPropertyName("achievements")]
    public SteamAchievementsBlock? Achievements { get; set; }
}

file sealed class SteamAchievementsBlock
{
    [System.Text.Json.Serialization.JsonPropertyName("total")]
    public int Total { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("highlighted")]
    public List<SteamAchievementItem>? Highlighted { get; set; }
}

file sealed class SteamAchievementItem
{
    [System.Text.Json.Serialization.JsonPropertyName("name")]
    public string? Name { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("path")]
    public string? Path { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("localized_name")]
    public string? LocalizedName { get; set; }
}

file sealed class RawgSearchRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("results")]
    public List<RawgSearchResultItem>? Results { get; set; }
}

file sealed class RawgSearchResultItem
{
    [System.Text.Json.Serialization.JsonPropertyName("id")]
    public long Id { get; set; }
}

file sealed class RawgAchievementsRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("count")]
    public int Count { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("results")]
    public List<RawgAchievementResultItem>? Results { get; set; }
}

file sealed class RawgAchievementResultItem
{
    [System.Text.Json.Serialization.JsonPropertyName("name")]
    public string? Name { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("description")]
    public string? Description { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("image")]
    public string? Image { get; set; }
}

file sealed class RawgSeriesRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("results")]
    public List<RawgSeriesItem>? Results { get; set; }
}

file sealed class RawgSeriesItem
{
    [System.Text.Json.Serialization.JsonPropertyName("id")]
    public long Id { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("name")]
    public string? Name { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("background_image")]
    public string? BackgroundImage { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("released")]
    public string? Released { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("rating")]
    public double? Rating { get; set; }
}

file sealed class TasteDiveRoot
{
    [System.Text.Json.Serialization.JsonPropertyName("Similar")]
    public TasteDiveSimilar? Similar { get; set; }
}

file sealed class TasteDiveSimilar
{
    [System.Text.Json.Serialization.JsonPropertyName("Results")]
    public List<TasteDiveItem>? Results { get; set; }
}

file sealed class TasteDiveItem
{
    [System.Text.Json.Serialization.JsonPropertyName("Name")]
    public string Name { get; set; } = string.Empty;

    [System.Text.Json.Serialization.JsonPropertyName("wTeaser")]
    public string? WTeaser { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("yUrl")]
    public string? YUrl { get; set; }
}

