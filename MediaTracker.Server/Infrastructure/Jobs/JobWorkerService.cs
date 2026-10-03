using MediaTracker.Server.Features.Jobs;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.Jobs;

/// <summary>
/// Drains the queue one job at a time. Sequential on purpose: the work is provider calls and
/// SQLite writes, so running several at once would only trade throughput for lock contention and a
/// burstier progress bar.
/// </summary>
public sealed class JobWorkerService(
    JobManager jobs,
    IServiceScopeFactory scopeFactory,
    ILogger<JobWorkerService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await foreach (var job in jobs.Reader.ReadAllAsync(stoppingToken).ConfigureAwait(false))
            {
                await RunAsync(job, stoppingToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
    }

    private async Task RunAsync(QueuedJob job, CancellationToken stoppingToken)
    {
        using var cts = jobs.CreateRunnerToken(job.JobId, stoppingToken);

        // The body reports its own checkpoints; the worker only owns the terminal states, which is
        // what guarantees a crashed or cancelled job still leaves a renderable state behind.
        var percent = 0;

        try
        {
            jobs.Publish(job, percent, "Запуск", JobStatus.Running, null);
            await using var scope = scopeFactory.CreateAsyncScope();

            // Reports are applied inline rather than through Progress<T>: the latter posts to the
            // thread pool, so a 90% checkpoint could overtake the 100% one that follows it.
            var progress = new InlineProgress(update =>
            {
                percent = update.ProgressPercent;
                jobs.Publish(job, percent, update.CurrentStep, update.Status, update.ErrorMessage);
            });

            await job.Work(scope.ServiceProvider, cts.Token, progress).ConfigureAwait(false);

            jobs.Publish(job, 100, "Готово", JobStatus.Completed, null);
        }
        catch (OperationCanceledException) when (cts.IsCancellationRequested)
        {
            jobs.Publish(job, percent, "Отменено", JobStatus.Cancelled, null, CancellationToken.None);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Background job {JobId} for media {MediaId} failed", job.JobId, job.MediaId);
            jobs.Publish(job, percent, "Ошибка", JobStatus.Failed, ex.Message, CancellationToken.None);
        }
        finally
        {
            // Fire and forget on purpose: the delay is cosmetic, and awaiting it would hold the
            // queue hostage for five seconds per finished job.
            _ = jobs.ForgetAfterDelayAsync(job.JobId);
        }
    }

    private sealed class InlineProgress(Action<JobProgressDto> report) : IProgress<JobProgressDto>
    {
        public void Report(JobProgressDto value) => report(value);
    }
}