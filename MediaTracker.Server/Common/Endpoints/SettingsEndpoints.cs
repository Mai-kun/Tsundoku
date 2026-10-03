using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Settings.GetCategoryOrder;
using MediaTracker.Server.Features.Settings.GetSourcePriority;
using MediaTracker.Server.Features.Settings.SaveCategoryOrder;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.Settings.SaveSourcePriority;
using MediaTracker.Server.Features.Settings.TestSource;
using MediaTracker.Server.Features.Settings.ToggleSource;
using MediaTracker.Server.Features.System.GetSources;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class SettingsEndpoints
{
    public static IEndpointRouteBuilder MapSettingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/settings");

        group.MapGet("/sources", ([FromServices] IGetSourcesHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk());

        group.MapPut("/sources/{id}/key", (
                string id,
                UpdateKeyRequest request,
                [FromServices] ISaveSourceKeyHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveSourceKeyCommand(id, request.ApiKey), ct).ToOk());

        group.MapPut("/sources/{id}/toggle", (
                string id,
                ToggleSourceRequest request,
                [FromServices] IToggleSourceHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new ToggleSourceCommand(id, request.Enabled), ct).ToOk());

        group.MapPost("/sources/{id}/test", (
                string id,
                [FromServices] ITestSourceHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new TestSourceQuery(id), ct).ToOk());

        group.MapGet("/category-order", ([FromServices] IGetCategoryOrderHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk());

        group.MapPut("/category-order", (
                string[] order,
                [FromServices] ISaveCategoryOrderHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveCategoryOrderCommand(order), ct).ToOk());

        group.MapGet("/source-priority", ([FromServices] IGetSourcePriorityHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk());

        group.MapPut("/source-priority", (
                Dictionary<string, string[]> priority,
                [FromServices] ISaveSourcePriorityHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveSourcePriorityCommand(priority), ct).ToOk());

        return app;
    }
}

public sealed record ToggleSourceRequest(bool Enabled);

public sealed record UpdateKeyRequest(string? ApiKey);
