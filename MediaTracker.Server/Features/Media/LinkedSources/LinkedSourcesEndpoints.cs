using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.EnrichMetadata;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Features.Media.LinkedSources;

/// <summary>
/// CRUD for the external sources bound to one title (the "Внешние источники" panel). The blob
/// seeds itself from the row's own ExternalSource/ExternalId, so legacy items render immediately.
/// </summary>
public static class LinkedSourcesEndpoints
{
    public static IEndpointRouteBuilder MapLinkedSourcesEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media/{id:guid}/linked-sources");

        group.MapGet("/", async (Guid id, AppDbContext db, CancellationToken ct) =>
        {
            var item = await db.LoadMediaItemAsync(id, ct);
            if (item is null) return Results.NotFound();

            return Results.Ok(LinkedSourceCatalog.GetFor(item));
        }).WithTags("Медиа / Media").WithSummary("Список привязанных внешних источников тайтла");

        group.MapPost("/", async (
            Guid id,
            [FromBody] LinkSourceRequest request,
            AppDbContext db,
            [FromServices] IEnrichMetadataHandler enrichHandler,
            CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Source) || string.IsNullOrWhiteSpace(request.ExternalId))
            {
                return Results.BadRequest(new { error = "source and externalId are required" });
            }

            var item = await db.LoadMediaItemAsync(id, ct);
            if (item is null) return Results.NotFound();

            var sources = LinkedSourceCatalog.GetFor(item);
            // "mangadex" typed or pasted becomes the canonical display name ("MangaDex"), so the
            // panel reads the same as rows the enrichment flow bound.
            var key = MediaMerger.GetCanonicalSourceName(request.Source.Trim());
            if (sources.Any(s => s.Source.Equals(key, StringComparison.OrdinalIgnoreCase)))
            {
                return Results.Conflict(new { error = $"Source '{key}' is already linked" });
            }

            var hasPrimary = sources.Any(s => s.IsPrimary);
            sources.Add(new LinkedSourceDto(
                key,
                request.ExternalId.Trim(),
                string.IsNullOrWhiteSpace(request.Url) ? null : request.Url!.Trim(),
                request.IsPrimary is true || !hasPrimary,
                string.IsNullOrWhiteSpace(request.Title) ? null : request.Title!.Trim(),
                request.ProvidedFields is { Count: > 0 } ? request.ProvidedFields : null));

            LinkedSourceCatalog.SaveFor(item, sources);
            await db.UpdateMediaItemAsync(item, ct);

            // A freshly bound source has data to give right now: fill the gaps from it
            // immediately, the same way the "Дополнить данные" action does.
            await enrichHandler.HandleAsync(new EnrichMetadataCommand(id, key), ct);

            return Results.Ok(sources);
        }).WithTags("Медиа / Media").WithSummary("Привязать внешний источник и дополнить данные из него");

        group.MapDelete("/{source}", async (
            Guid id,
            string source,
            AppDbContext db,
            CancellationToken ct) =>
        {
            var item = await db.LoadMediaItemAsync(id, ct);
            if (item is null) return Results.NotFound();

            var sources = LinkedSourceCatalog.GetFor(item);
            var removed = sources.FirstOrDefault(s => s.Source.Equals(source, StringComparison.OrdinalIgnoreCase));
            if (removed is null) return Results.NotFound(new { error = $"Source '{source}' is not linked" });

            sources.Remove(removed);
            // Removing the primary binding hands the flag to the first remaining source.
            if (removed.IsPrimary && sources.Count > 0)
            {
                sources[0] = sources[0] with { IsPrimary = true };
            }

            LinkedSourceCatalog.SaveFor(item, sources);
            await db.UpdateMediaItemAsync(item, ct);
            return Results.Ok(sources);
        }).WithTags("Медиа / Media").WithSummary("Отвязать внешний источник");

        group.MapPut("/{source}/primary", async (
            Guid id,
            string source,
            AppDbContext db,
            [FromServices] IRefreshMetadataHandler refreshHandler,
            CancellationToken ct) =>
        {
            var item = await db.LoadMediaItemAsync(id, ct);
            if (item is null) return Results.NotFound();

            var sources = LinkedSourceCatalog.GetFor(item);
            var target = sources.FirstOrDefault(s => s.Source.Equals(source, StringComparison.OrdinalIgnoreCase));
            if (target is null) return Results.NotFound(new { error = $"Source '{source}' is not linked" });

            var result = new List<LinkedSourceDto>();
            foreach (var s in sources)
            {
                result.Add(s with { IsPrimary = ReferenceEquals(s, target) || s.Source == target.Source });
            }

            // The base record follows the crown: the promoted source becomes the source the title
            // itself is bound to, so the next refresh and the aggregator query IT first.
            item.ExternalSource = target.Source;
            if (!string.IsNullOrWhiteSpace(target.ExternalId))
            {
                item.ExternalId = target.ExternalId;
            }

            LinkedSourceCatalog.SaveFor(item, result);
            await db.UpdateMediaItemAsync(item, ct);

            // The newly appointed source is authoritative: its poster, status and chapter counts
            // must be in the card, not only in the binding table. The refresh runs as a job from
            // the re-pointed source; the client re-fetches the card and picks the result up.
            if (!string.IsNullOrWhiteSpace(item.ExternalId))
            {
                await refreshHandler.HandleAsync(
                    new RefreshMetadataCommand(id, FillMissingOnly: false, UpdateMainCover: true), ct);
            }

            return Results.Ok(result);
        }).WithTags("Медиа / Media").WithSummary("Назначить источник основным и синхронизировать данные");

        return app;
    }
}
