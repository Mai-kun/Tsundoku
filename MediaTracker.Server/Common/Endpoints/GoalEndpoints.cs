using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Goals;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class GoalEndpoints
{
    public static IEndpointRouteBuilder MapGoalEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/goals");

        group.MapGet("/", async (
                [FromServices] IGoalsHandler handler,
                [FromServices] ILogger<IGoalsHandler> logger,
                int? year,
                CancellationToken ct) =>
            {
                var targetYear = year ?? DateTime.UtcNow.Year;
                try
                {
                    var result = await handler.GetGoalsAsync(targetYear, ct);
                    return (IResult)result.ToOk();
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Failed to load goals for year {Year}", year);
                    return Results.Problem("Failed to load goals");
                }
            })
            .WithTags("Цели / Goals")
            .WithSummary("Цели за год с рассчитанным прогрессом")
            .WithDescription("Возвращает годовые и тематические цели с живым прогрессом по завершённым тайтлам и превью обложек.");

        group.MapPost("/", (
                CreateGoalRequest request,
                [FromServices] IGoalsHandler handler,
                CancellationToken ct) =>
            handler.CreateAsync(request, ct).ToOk())
            .WithTags("Цели / Goals")
            .WithSummary("Создать цель")
            .WithDescription("Создаёт годовую или тематическую цель (категория, целевое число, опциональный smart-запрос).");

        group.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IGoalsHandler handler,
                CancellationToken ct) =>
            handler.DeleteAsync(id, ct).ToNoContent())
            .WithTags("Цели / Goals")
            .WithSummary("Удалить цель");

        return app;
    }
}
