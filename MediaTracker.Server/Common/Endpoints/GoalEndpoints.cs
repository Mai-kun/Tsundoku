using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Goals;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class GoalEndpoints
{
    public static IEndpointRouteBuilder MapGoalEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/goals");

        group.MapGet("/", (
                [FromServices] IGoalsHandler handler,
                int? year,
                CancellationToken ct) =>
            handler.GetGoalsAsync(year ?? DateTime.UtcNow.Year, ct).ToOk())
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
