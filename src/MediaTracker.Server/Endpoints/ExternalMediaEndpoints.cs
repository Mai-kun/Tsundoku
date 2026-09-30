using System.Collections.Frozen;
using MediaTracker.Server.Services.External;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Endpoints;

public static class ExternalMediaEndpoints
{
    private static readonly FrozenSet<string> SupportedTypes = new[] { "all", "game", "movie", "tvshow", "anime", "manga", "book" }
        .ToFrozenSet(StringComparer.OrdinalIgnoreCase);

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
        var normalizedType = string.IsNullOrWhiteSpace(type) ? "anime" : type.Trim();
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
        var normalizedType = string.IsNullOrWhiteSpace(type) ? "all" : type.Trim();
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
        RawgGameService gameService,
        CancellationToken ct)
    {
        var achievements = await gameService.GetAchievementsAsync(
            steamAppId, rawgId, title, externalSource, externalId, ct);
        return Results.Ok(achievements);
    }

    private static async Task<IResult> GetGameRelated(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        RawgGameService gameService,
        CancellationToken ct)
    {
        var related = await gameService.GetRelatedAsync(rawgId, title, externalSource, externalId, ct);
        return Results.Ok(related);
    }

    private static async Task<IResult> GetGameRecommendations(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        RawgGameService gameService,
        CancellationToken ct)
    {
        var recommendations = await gameService.GetRecommendationsAsync(rawgId, title, externalSource, externalId, ct);
        return Results.Ok(recommendations);
    }
}
public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
public sealed record TranslateResponse(string TranslatedText);

