using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class SeasonEndpoints
{
    public static IEndpointRouteBuilder MapSeasonEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/seasons");

        group.MapPut("/{id:guid}/progress", (
                Guid id,
                UpdateSeasonProgressRequest request,
                [FromServices] IUpdateSeasonProgressHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateSeasonProgressCommand(id, request.CurrentEpisode), ct).ToNoContent());

        return app;
    }
}
