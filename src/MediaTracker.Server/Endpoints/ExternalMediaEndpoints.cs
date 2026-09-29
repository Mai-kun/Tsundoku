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
}

public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
public sealed record TranslateResponse(string TranslatedText);

