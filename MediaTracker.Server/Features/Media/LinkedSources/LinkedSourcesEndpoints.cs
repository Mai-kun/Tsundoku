using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
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
            CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(request.Source) || string.IsNullOrWhiteSpace(request.ExternalId))
            {
                return Results.BadRequest(new { error = "source and externalId are required" });
            }

            var item = await db.LoadMediaItemAsync(id, ct);
            if (item is null) return Results.NotFound();

            var sources = LinkedSourceCatalog.GetFor(item);
            var key = request.Source.Trim();
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
                string.IsNullOrWhiteSpace(request.Details) ? null : request.Details!.Trim()));

            LinkedSourceCatalog.SaveFor(item, sources);
            await db.UpdateMediaItemAsync(item, ct);
            return Results.Ok(sources);
        }).WithTags("Медиа / Media").WithSummary("Привязать внешний источник");

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

            LinkedSourceCatalog.SaveFor(item, result);
            await db.UpdateMediaItemAsync(item, ct);
            return Results.Ok(result);
        }).WithTags("Медиа / Media").WithSummary("Назначить источник основным");

        return app;
    }
}
