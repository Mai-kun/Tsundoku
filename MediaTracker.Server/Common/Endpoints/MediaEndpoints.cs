using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.External.EnrichMetadata;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.External.RelinkMedia;
using MediaTracker.Server.Features.History.ClearHistory;
using MediaTracker.Server.Features.History.DeleteHistoryEvent;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.DeleteMedia;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.GetRecommendations;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class MediaEndpoints
{
    public static IEndpointRouteBuilder MapMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media");

        group.MapGet("/", (
                [FromServices] IGetMediaListHandler handler,
                string? type,
                MediaStatus? status,
                bool? isAnime,
                string? search,
                string? sortBy,
                string? sortOrder,
                CancellationToken ct) =>
            handler.HandleAsync(new GetMediaListQuery(type, status, isAnime, search, sortBy, sortOrder), ct)
                .ToOk());

        group.MapGet("/stats", ([FromServices] IGetMediaStatsHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk());

        group.MapGet("/{id:guid}", (
                Guid id,
                [FromServices] IGetMediaDetailHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new GetMediaDetailQuery(id), ct).ToOk());

        group.MapPost("/", async (
            CreateMediaRequest request,
            [FromServices] ICreateMediaHandler handler,
            CancellationToken ct) =>
        {
            var result = await handler.HandleAsync(new CreateMediaCommand(request), ct);

            if (!result.TryGetValue(out var created))
            {
                return HttpResultMapper.Problem(result.Error!);
            }

            return Results.Created($"/api/media/{created.Id}", created);
        });

        group.MapPut("/{id:guid}", (
                Guid id,
                UpdateMediaRequest request,
                [FromServices] IUpdateMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateMediaCommand(id, request), ct).ToOk());

        group.MapPut("/{id:guid}/status", (
                Guid id,
                UpdateStatusRequest request,
                [FromServices] IUpdateStatusHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateStatusCommand(id, request.Status), ct).ToNoContent());

        group.MapPut("/{id:guid}/progress", (
                Guid id,
                UpdateProgressRequest request,
                [FromServices] IUpdateProgressHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateProgressCommand(id, request.CurrentProgress), ct).ToNoContent());

        // Safe-merge: the client sends fillMissing when the user picked "keep my edits" in the
        // refresh dialog, which turns the overwrite into a gap fill.
        group.MapPost("/{id:guid}/refresh", (
                Guid id,
                [FromBody] RefreshMetadataRequest? request,
                [FromServices] IRefreshMetadataHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new RefreshMetadataCommand(id, request?.FillMissing ?? false),
                ct).ToOk());

        // "Дополнить": same gap-fill rules, but the source is the one the user picked in the dialog
        // rather than whatever the row was originally matched on.
        group.MapPost("/{id:guid}/enrich", (
                Guid id,
                [FromBody] EnrichMetadataRequest? request,
                [FromServices] IEnrichMetadataHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new EnrichMetadataCommand(id, request?.Source),
                ct).ToOk());

        // Re-link: point an existing row at another provider's entity (Kinopoisk -> TMDb).
        group.MapPost("/{id:guid}/relink", (
                Guid id,
                RelinkMediaRequest request,
                [FromServices] IRelinkMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new RelinkMediaCommand(id, request), ct).ToOk());

        // Recommendations live on the row, so this one endpoint both fetches and replays: a call inside the
        // 30-day window is answered from SQLite without the provider being contacted at all.
        group.MapPost("/{id:guid}/recommendations", (
                Guid id,
                string? source,
                bool? forceRefresh,
                [FromServices] IGetRecommendationsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetRecommendationsCommand(id, source, forceRefresh ?? false),
                ct).ToOk());

        group.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IDeleteMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new DeleteMediaCommand(id), ct).ToNoContent());

        var historyGroup = app.MapGroup("/api/history");

        historyGroup.MapGet("/", ([FromServices] IGetHistoryEventsHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk());

        historyGroup.MapDelete("/", ([FromServices] IClearHistoryHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToNoContent());

        historyGroup.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IDeleteHistoryEventHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new DeleteHistoryEventCommand(id), ct).ToNoContent());

        return app;
    }
}

public sealed record RefreshMetadataRequest(bool FillMissing = false);

public sealed record EnrichMetadataRequest(string? Source = null);
