using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Volumes.AddVolume;
using MediaTracker.Server.Features.Volumes.DeleteVolume;
using MediaTracker.Server.Features.Volumes.UpdateVolume;
using MediaTracker.Server.Features.Volumes.UpdateVolumeProgress;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class VolumeEndpoints
{
    public static IEndpointRouteBuilder MapVolumeEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/volumes");

        group.MapPut("/{id:guid}/progress", (
                Guid id,
                UpdateVolumeProgressRequest request,
                [FromServices] IUpdateVolumeProgressHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new UpdateVolumeProgressCommand(id, request.CurrentPage, request.CurrentChapter),
                ct).ToNoContent());

        group.MapPost("/", (
            CreateVolumeRequest request,
            Guid mangaId,
            [FromServices] IAddVolumeHandler handler,
            CancellationToken ct) =>
            handler.HandleAsync(new AddVolumeCommand(mangaId, request), ct).ToOk());

        group.MapPut("/{id:guid}", (
                Guid id,
                UpdateVolumeRequest request,
                [FromServices] IUpdateVolumeHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateVolumeCommand(id, request), ct).ToOk());

        group.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IDeleteVolumeHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new DeleteVolumeCommand(id), ct).ToNoContent());

        return app;
    }
}
