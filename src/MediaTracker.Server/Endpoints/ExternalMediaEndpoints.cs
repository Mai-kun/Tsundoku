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
        IHttpClientFactory httpClientFactory,
        Microsoft.Extensions.Caching.Memory.IMemoryCache cache,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
        {
            return Results.BadRequest(new { message = "Text is required." });
        }

        var cleanText = System.Text.RegularExpressions.Regex.Replace(request.Text, "<.*?>", " ").Trim();
        if (string.IsNullOrWhiteSpace(cleanText))
        {
            return Results.Ok(new TranslateResponse(request.Text));
        }

        var target = string.IsNullOrWhiteSpace(request.TargetLanguage) ? "ru" : request.TargetLanguage.Trim().ToLowerInvariant();
        var cacheKey = $"translate:{target}:{cleanText.GetHashCode()}";
        if (cache.TryGetValue(cacheKey, out string? cached) && !string.IsNullOrWhiteSpace(cached))
        {
            return Results.Ok(new TranslateResponse(cached));
        }

        var client = httpClientFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(8);
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36");

        // Strategy 1: Google client=dict-chrome-ex
        try
        {
            var googleUrl = $"https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl={Uri.EscapeDataString(target)}&q={Uri.EscapeDataString(cleanText)}";
            using var response = await client.GetAsync(googleUrl, ct);
            if (response.IsSuccessStatusCode)
            {
                using var jsonDoc = await System.Text.Json.JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
                var root = jsonDoc.RootElement;
                string? translated = null;
                if (root.ValueKind == System.Text.Json.JsonValueKind.Array && root.GetArrayLength() > 0)
                {
                    var first = root[0];
                    if (first.ValueKind == System.Text.Json.JsonValueKind.Array && first.GetArrayLength() > 0)
                    {
                        translated = first[0].GetString();
                    }
                    else if (first.ValueKind == System.Text.Json.JsonValueKind.String)
                    {
                        translated = first.GetString();
                    }
                }

                if (!string.IsNullOrWhiteSpace(translated))
                {
                    cache.Set(cacheKey, translated, TimeSpan.FromHours(24));
                    return Results.Ok(new TranslateResponse(translated));
                }
            }
        }
        catch
        {
            // Fall back to MyMemory
        }

        // Strategy 2: MyMemory Translate
        try
        {
            var myMemoryUrl = $"https://api.mymemory.translated.net/get?q={Uri.EscapeDataString(cleanText)}&langpair=auto|{Uri.EscapeDataString(target)}";
            using var response = await client.GetAsync(myMemoryUrl, ct);
            if (response.IsSuccessStatusCode)
            {
                using var jsonDoc = await System.Text.Json.JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
                if (jsonDoc.RootElement.TryGetProperty("responseData", out var respData) &&
                    respData.TryGetProperty("translatedText", out var transElem))
                {
                    var translated = transElem.GetString();
                    if (!string.IsNullOrWhiteSpace(translated))
                    {
                        cache.Set(cacheKey, translated, TimeSpan.FromHours(24));
                        return Results.Ok(new TranslateResponse(translated));
                    }
                }
            }
        }
        catch
        {
            // Return original text if translation service unavailable
        }

        return Results.Ok(new TranslateResponse(cleanText));
    }
}

public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
public sealed record TranslateResponse(string TranslatedText);

