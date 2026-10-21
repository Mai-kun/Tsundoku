using FluentValidation;
using MediaTracker.Server.Features.Lists;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class ListEndpoints
{
    public static IEndpointRouteBuilder MapListEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/lists");
        group.MapGet("/", async (ListsService service, CancellationToken ct) =>
            Results.Ok(await service.GetListsAsync(ct)))
            .WithTags("Коллекции / Lists")
            .WithSummary("Список коллекций (ручных и умных)");

        group.MapGet("/{id:guid}", async (Guid id, ListsService service, CancellationToken ct) =>
            await service.GetListDetailAsync(id, ct) is { } detail ? Results.Ok(detail) : Results.NotFound())
            .WithTags("Коллекции / Lists")
            .WithSummary("Содержимое списка и тайтлы");

        group.MapPost("/", async (
            [FromBody] CreateListRequest request, IValidator<CreateListRequest> validator,
            ListsService service, CancellationToken ct) =>
        {
            var validation = await validator.ValidateAsync(request, ct);
            if (!validation.IsValid) return Results.ValidationProblem(validation.ToDictionary());
            var id = await service.CreateAsync(request, ct);
            return Results.Created($"/api/lists/{id}", new { id });
        })
        .WithTags("Коллекции / Lists")
        .WithSummary("Создать обычный или умный список с правилами");

        group.MapPut("/{id:guid}", async (
            Guid id, [FromBody] UpdateListRequest request, IValidator<UpdateListRequest> validator,
            ListsService service, CancellationToken ct) =>
        {
            var validation = await validator.ValidateAsync(request, ct);
            if (!validation.IsValid) return Results.ValidationProblem(validation.ToDictionary());
            return await service.UpdateAsync(id, request, ct) ? Results.NoContent() : Results.NotFound();
        })
        .WithTags("Коллекции / Lists")
        .WithSummary("Обновить параметры или правила списка");

        group.MapDelete("/{id:guid}", async (Guid id, ListsService service, CancellationToken ct) =>
            await service.DeleteAsync(id, ct) ? Results.NoContent() : Results.NotFound())
            .WithTags("Коллекции / Lists")
            .WithSummary("Удалить список");

        group.MapPost("/{id:guid}/items", async (
            Guid id, [FromBody] AddMediaToListRequest request, ListsService service, CancellationToken ct) =>
            await service.AddMediaAsync(id, request.MediaId, ct) ? Results.NoContent() : Results.NotFound())
            .WithTags("Коллекции / Lists")
            .WithSummary("Добавить тайтл в ручной список");

        group.MapDelete("/{id:guid}/items/{mediaId:guid}", async (
            Guid id, Guid mediaId, ListsService service, CancellationToken ct) =>
            await service.RemoveMediaAsync(id, mediaId, ct) ? Results.NoContent() : Results.NotFound())
            .WithTags("Коллекции / Lists")
            .WithSummary("Убрать тайтл из списка");

        app.MapGet("/api/media/{mediaId:guid}/lists", async (
            Guid mediaId, ListsService service, CancellationToken ct) =>
            Results.Ok(await service.GetListsForMediaAsync(mediaId, ct)))
            .WithTags("Коллекции / Lists")
            .WithSummary("Списки, в которые входит тайтл");

        return app;
    }
}
