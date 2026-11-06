using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Shared idle clock: every API request is a heartbeat from the desktop shell's web view, so the
/// service below can tell "the window has been closed / user is away" from "the UI is live".
/// </summary>
public sealed class IdleState
{
    private long _lastActivityTicks = DateTime.UtcNow.Ticks;

    public DateTime LastActivityUtc => new(Interlocked.Read(ref _lastActivityTicks), DateTimeKind.Utc);

    public void Touch() => Interlocked.Exchange(ref _lastActivityTicks, DateTime.UtcNow.Ticks);

    public TimeSpan IdleFor(DateTime now) => now - LastActivityUtc;
}

/// <summary>
/// Marks every incoming request as activity. Long-lived streams (the job SSE feed) count once at
/// connection time, which is fine: an open stream means an open UI, and the trim it then misses is
/// re-armed by the next regular request the UI makes.
/// </summary>
public sealed class IdleDetectionMiddleware(RequestDelegate next, IdleState idle)
{
    public async Task InvokeAsync(HttpContext context)
    {
        idle.Touch();
        await next(context);
    }
}

/// <summary>
/// The idle-sleep loop: while no request has arrived for five minutes and no background job is
/// running, the backend trims its memory once. The window stays fully responsive — "sleep" only
/// returns the freed pages to the OS; the next request costs nothing extra and re-arms the cycle.
/// </summary>
public sealed class IdleDetectionService(
    IdleState idle,
    IJobManager jobManager,
    IMemoryCache cache,
    AppPaths appPaths,
    ILogger<IdleDetectionService> logger) : BackgroundService
{
    private static readonly TimeSpan IdleThreshold = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan CheckInterval = TimeSpan.FromMinutes(1);

    /// <summary>True while one idle episode is already trimmed, so the log line fires once per sleep, not once a minute.</summary>
    private bool _sleeping;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation(
            "[Memory] Idle sleep armed: trims after {Threshold} without requests or jobs.",
            IdleThreshold);

        using var timer = new PeriodicTimer(CheckInterval);
        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            if (jobManager.GetSnapshot().Any(job => job.Status is JobStatus.Queued or JobStatus.Running))
            {
                // Work in flight may both need and free memory; a trim here would fight the job.
                _sleeping = false;
                continue;
            }

            if (idle.IdleFor(DateTime.UtcNow) < IdleThreshold)
            {
                _sleeping = false;
                continue;
            }

            if (_sleeping)
            {
                continue;
            }

            _sleeping = true;
            var before = MemoryOptimizer.TakeSnapshot();
            MemoryOptimizer.TrimMemory(cache, $"Data Source={appPaths.DatabaseFilePath}");
            var after = MemoryOptimizer.TakeSnapshot();
            logger.LogInformation(
                "[Memory] Server entered idle sleep mode. Memory trimmed. Working set {BeforeMb} MB -> {AfterMb} MB.",
                before.WorkingSetMb,
                after.WorkingSetMb);
        }
    }
}
