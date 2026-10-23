using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Jobs;

/// <summary>
/// Hourly sweep for titles whose auto-refresh date has come due. Five titles per cycle, three
/// seconds between API calls: the external providers throttle hard, and a burst poll reads exactly
/// like the scraping they ban for.
/// </summary>
public sealed class AutoRefreshWorker(
    IServiceScopeFactory scopeFactory,
    ILogger<AutoRefreshWorker> logger) : BackgroundService
{
    private static readonly TimeSpan StartupDelay = TimeSpan.FromSeconds(45);

    private static readonly TimeSpan CycleDelay = TimeSpan.FromHours(1);

    /// <summary>Cool-down between two providers calls inside one cycle.</summary>
    private static readonly TimeSpan PerItemDelay = TimeSpan.FromSeconds(3);

    private const int BatchSize = 5;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(StartupDelay, stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunCycleAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "[AutoRefresh] Cycle failed; retrying on the next tick");
            }

            try
            {
                await Task.Delay(CycleDelay, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    private async Task RunCycleAsync(CancellationToken ct)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var aggregator = scope.ServiceProvider.GetRequiredService<MetadataAggregatorService>();

        var overdue = await db.MediaItems
            .Include(m => (m as TvShow)!.Seasons)
            .Include(m => (m as Manga)!.Volumes)
            .Where(m => m.NextAutoRefreshAt != null
                     && m.NextAutoRefreshAt <= DateTime.UtcNow
                     && m.ReleaseStatus != ReleaseStatusRules.Finished
                     && m.Status != MediaStatus.Dropped)
            .OrderBy(m => m.NextAutoRefreshAt)
            .Take(BatchSize)
            .ToListAsync(ct);

        foreach (var item in overdue)
        {
            ct.ThrowIfCancellationRequested();
            await Task.Delay(PerItemDelay, ct);
            await AutoRefreshRunner.RunAsync(db, aggregator, logger, item, ct);
        }
    }
}
