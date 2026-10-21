using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.External.GetExternalDetails;
using MediaTracker.Server.Features.External.GetGameAchievements;
using MediaTracker.Server.Features.External.GetGameRecommendations;
using MediaTracker.Server.Features.External.GetGameRelated;
using MediaTracker.Server.Features.External.SearchExternal;
using MediaTracker.Server.Features.External.GetExternalRelations;
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
                string? source,
                bool? byCreator,
                [FromServices] ISearchExternalHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SearchExternalQuery(type, query, source, byCreator == true), ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Поиск по внешним базам (с поддержкой выбора источника и студии/автора)");

        group.MapGet("/details", (
                string? type,
                string? id,
                string? title,
                string? source,
                [FromServices] IGetExternalDetailsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new GetExternalDetailsQuery(type, id, title, source), ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Детальные метаданные из внешнего источника");

        group.MapPost("/translate", (
                TranslateRequest request,
                [FromServices] ITranslateTextHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new TranslateTextCommand(request.Text, request.TargetLanguage), ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Машинный перевод синопсиса");

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
                ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Список достижений игры");

        group.MapGet("/games/related", (
                string? rawgId,
                string? title,
                string? externalSource,
                string? externalId,
                [FromServices] IGetGameRelatedHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetGameRelatedQuery(rawgId, title, externalSource, externalId),
                ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Связанные игры (DLC, спин-оффы, серии)");

        group.MapGet("/games/recommendations", (
                string? rawgId,
                string? title,
                string? externalSource,
                string? externalId,
                [FromServices] IGetGameRecommendationsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetGameRecommendationsQuery(rawgId, title, externalSource, externalId),
                ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Рекомендации похожих игр");

        // Relations are requested explicitly, never on card open. `kind` picks the relationship:
        // "related" is the full pool, "recommendations" is what the source itself recommends.
        group.MapGet("/relations", (
                string? type,
                string? externalId,
                string? title,
                string? source,
                string? kind,
                [FromServices] IGetExternalRelationsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetExternalRelationsQuery(type, externalId, title, source, kind),
                ct).ToOk())
            .WithTags("Внешний поиск / External")
            .WithSummary("Связанные тайтлы франшизы");

        return app;
    }
}

public sealed record TranslateRequest(string Text, string? TargetLanguage = "ru");
