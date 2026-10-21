using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Features.Logs.ClientLog;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class LogEndpoints
{
    public static IEndpointRouteBuilder MapLogEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/logs/client", (
                ClientLogRequest request,
                [FromServices] IClientLogHandler handler) =>
            handler.Handle(request).ToNoContent())
            .WithTags("Система / System")
            .WithSummary("Запись клиентских логов")
            .WithDescription("Принимает сообщения об ошибках и событиях с фронтенда для централизованного логирования на сервере.");

        return app;
    }
}
