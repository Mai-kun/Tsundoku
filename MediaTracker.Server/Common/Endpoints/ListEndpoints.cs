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
            Results.Ok(await service.GetListsAsync(ct)));
        group.MapGet("/{id:guid}", async (Guid id, ListsService service, CancellationToken ct) =>
            await service.GetListDetailAsync(id, ct) is { } detail ? Results.Ok(detail) : Results.NotFound());
        group.MapPost("/", async (
            [FromBody] CreateListRequest request, IValidator<CreateListRequest> validator,
            ListsService service, CancellationToken ct) =>
        {
            var validation = await validator.ValidateAsync(request, ct);
            if (!validation.IsValid) return Results.ValidationProblem(validation.ToDictionary());
            var id = await service.CreateAsync(request, ct);
            return Results.Created($"/api/lists/{id}", new { id });
        });
        group.MapPut("/{id:guid}", async (
            Guid id, [FromBody] UpdateListRequest request, IValidator<UpdateListRequest> validator,
            ListsService service, CancellationToken ct) =>
        {
            var validation = await validator.ValidateAsync(request, ct);
            if (!validation.IsValid) return Results.ValidationProblem(validation.ToDictionary());
            return await service.UpdateAsync(id, request, ct) ? Results.NoContent() : Results.NotFound();
        });
        group.MapDelete("/{id:guid}", async (Guid id, ListsService service, CancellationToken ct) =>
            await service.DeleteAsync(id, ct) ? Results.NoContent() : Results.NotFound());
        group.MapPost("/{id:guid}/items", async (
            Guid id, [FromBody] AddMediaToListRequest request, ListsService service, CancellationToken ct) =>
            await service.AddMediaAsync(id, request.MediaId, ct) ? Results.NoContent() : Results.NotFound());
        group.MapDelete("/{id:guid}/items/{mediaId:guid}", async (
            Guid id, Guid mediaId, ListsService service, CancellationToken ct) =>
            await service.RemoveMediaAsync(id, mediaId, ct) ? Results.NoContent() : Results.NotFound());
        app.MapGet("/api/media/{mediaId:guid}/lists", async (
            Guid mediaId, ListsService service, CancellationToken ct) =>
            Results.Ok(await service.GetListsForMediaAsync(mediaId, ct)));
        return app;
    }
}
