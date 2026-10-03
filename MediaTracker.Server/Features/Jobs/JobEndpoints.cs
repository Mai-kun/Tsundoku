using System.Text.Json;
using MediaTracker.Server.Infrastructure.Jobs;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Features.Jobs;

public static class JobEndpoints
{
    /// <summary>Web defaults: camelCase property names, to match what GET /api/jobs returns.</summary>
    private static readonly JsonSerializerOptions StreamJson = new(JsonSerializerDefaults.Web);

    public static IEndpointRouteBuilder MapJobEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/jobs");

        group.MapGet("/", ([FromServices] IJobManager jobs) => Results.Ok(jobs.GetSnapshot()));

        group.MapGet("/stream", async (
            HttpContext context,
            [FromServices] IJobManager jobs,
            CancellationToken ct) =>
        {
            var response = context.Response;
            response.ContentType = "text/event-stream";
            response.Headers.CacheControl = "no-cache";
            // Proxies buffer by default, which would hold every update until the buffer fills.
            response.Headers.Connection = "keep-alive";
            response.Headers["X-Accel-Buffering"] = "no";

            await response.Body.FlushAsync(ct).ConfigureAwait(false);

            // The snapshot goes out first: a client that connects mid-job would otherwise render an
            // empty Activity Center until the next checkpoint arrived.
            foreach (var job in jobs.GetSnapshot())
            {
                await WriteAsync(response, job, ct).ConfigureAwait(false);
            }

            await foreach (var job in jobs.SubscribeAsync(ct).ConfigureAwait(false))
            {
                await WriteAsync(response, job, ct).ConfigureAwait(false);
            }
        });

        group.MapPost("/{id:guid}/cancel", (
            Guid id,
            [FromServices] IJobManager jobs) =>
            jobs.CancelJob(id) ? Results.NoContent() : Results.NotFound());

        return app;
    }

    private static Task WriteAsync(HttpResponse response, JobProgressDto job, CancellationToken ct) =>
        response.WriteAsync($"data: {JsonSerializer.Serialize(job, StreamJson)}\n\n", ct);
}