using System.Threading.Channels;
using MediaTracker.Server.Features.Jobs;

namespace MediaTracker.Server.Infrastructure.Jobs;

/// <summary>One unit of queued work plus the identity every progress report is stamped with.</summary>
public sealed record QueuedJob(
    Guid JobId,
    Guid? MediaId,
    string Title,
    DateTime StartedAt,
    Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> Work);

/// <summary>
/// Runs work off the request thread and broadcasts its progress. Everything lives in memory on
/// purpose: a job is a short-lived side effect of adding a title, so persisting it would buy
/// nothing that a restart could not simply re-run.
/// </summary>
public interface IJobManager
{
    /// <summary>Queues a job and returns its id so the caller can cancel it later.</summary>
    Guid Enqueue(
        Guid? mediaId,
        string title,
        Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> work);

    /// <summary>Snapshot of the jobs the UI has to draw right now.</summary>
    IReadOnlyList<JobProgressDto> GetSnapshot();

    /// <summary>Requests cancellation. False when the job is already gone.</summary>
    bool CancelJob(Guid jobId);

    /// <summary>Live feed for the SSE endpoint; ends when <paramref name="ct"/> fires.</summary>
    IAsyncEnumerable<JobProgressDto> SubscribeAsync(CancellationToken ct);

    /// <summary>The queue the worker drains. Exposed so the worker stays a separate hosted service.</summary>
    ChannelReader<QueuedJob> Reader { get; }

    /// <summary>
    /// Token source for one run: it fires when the user cancels the job or when the host stops.
    /// Owned by the caller so the worker can dispose it, and linked against the per-job source
    /// created at enqueue time — that is the only way a job cancelled while still queued ever sees
    /// the cancellation.
    /// </summary>
    CancellationTokenSource CreateRunnerToken(Guid jobId, CancellationToken stoppingToken);
}