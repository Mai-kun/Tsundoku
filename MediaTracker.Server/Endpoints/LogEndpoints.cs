using MediaTracker.Server.DTOs;

namespace MediaTracker.Server.Endpoints;

public static class LogEndpoints
{
    public static IEndpointRouteBuilder MapLogEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/logs/client", (ClientLogRequest request, ILogger<Program> logger) =>
        {
            var stack = string.IsNullOrWhiteSpace(request.Stack) ? string.Empty : $"\n{request.Stack}";
            logger.LogError("[Frontend Error] {Message} at {Url}{Stack}", request.Message, request.Url ?? "unknown", stack);
            return Results.Ok();
        });

        return app;
    }
}
