using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.External.GetExternalDetails;
using MediaTracker.Server.Features.External.GetGameAchievements;
using MediaTracker.Server.Features.External.GetGameRecommendations;
using MediaTracker.Server.Features.External.GetGameRelated;
using MediaTracker.Server.Features.External.SearchExternal;
using MediaTracker.Server.Features.External.TranslateText;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class ExternalMediaEndpoints
{
    public static IEndpointRouteBuilder MapExternalMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/external");

        group.MapGet("/search", (
                string? type,
                string? query,
                [FromServices] ISearchExternalHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SearchExternalQuery(type, query), ct).ToOk());

        group.MapGet("/details", (
                string? type,
                string? id,
                string? title,
                string? source,
                [FromServices] IGetExternalDetailsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new GetExternalDetailsQuery(type, id, title, source), ct).ToOk());

        group.MapPost("/translate", (
                TranslateRequest request,
                [FromServices] ITranslateTextHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new TranslateTextCommand(request.Text, request.TargetLanguage), ct).ToOk());

        group.MapGet("/games/achievements", (
                string? steamAppId,
                string? rawgId,
                string? title,
                string? externalSource,
                string? externalId,
                [FromServices] IGetGameAchievementsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetGameAchievementsQuery(steamAppId, rawgId, title, externalSource, externalId),
                ct).ToOk());

        group.MapGet("/games/related", (
                string? rawgId,
                string? title,
                string? externalSource,
                string? externalId,
                [FromServices] IGetGameRelatedHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetGameRelatedQuery(rawgId, title, externalSource, externalId),
                ct).ToOk());

        group.MapGet("/games/recommendations", (
                string? rawgId,
                string? title,
                string? externalSource,
                string? externalId,
                [FromServices] IGetGameRecommendationsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetGameRecommendationsQuery(rawgId, title, externalSource, externalId),
                ct).ToOk());

        return app;
    }
}

public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
