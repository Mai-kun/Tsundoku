using MediaTracker.Server.Services.External;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Middleware;

public sealed class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IHostEnvironment environment) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        // An unreachable upstream provider is a bad gateway, not a bug on our side.
        if (exception is SourceUnavailableException sourceUnavailable)
        {
            logger.LogWarning(
                sourceUnavailable.InnerException ?? sourceUnavailable,
                "External metadata source '{Source}' is unavailable on {Path}",
                sourceUnavailable.SourceId,
                httpContext.Request.Path);

            await WriteProblemAsync(
                httpContext,
                cancellationToken,
                StatusCodes.Status502BadGateway,
                "External metadata source is unavailable.",
                sourceUnavailable.Message);

            return true;
        }

        logger.LogError(
            exception,
            "Unhandled exception on {Path}: {Message}",
            httpContext.Request.Path,
            exception.Message);

        await WriteProblemAsync(
            httpContext,
            cancellationToken,
            StatusCodes.Status500InternalServerError,
            "An unexpected error occurred.",
            exception.Message);

        return true;
    }

    private async ValueTask WriteProblemAsync(
        HttpContext httpContext,
        CancellationToken cancellationToken,
        int status,
        string title,
        string detail)
    {
        httpContext.Response.StatusCode = status;
        httpContext.Response.ContentType = "application/problem+json";

        await httpContext.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Title = title,
            Status = status,
            // Outside development the message may carry upstream or file-system detail, so it stays hidden.
            Detail = environment.IsDevelopment() ? detail : null,
            Instance = httpContext.Request.Path,
        }, cancellationToken);
    }
}