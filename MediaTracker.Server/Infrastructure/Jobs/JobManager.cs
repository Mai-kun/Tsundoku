using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Threading.Channels;
using MediaTracker.Server.Features.Jobs;

namespace MediaTracker.Server.Infrastructure.Jobs;

/// <summary>
/// The in-memory registry, the SSE bus and the cancellation registry in one object: they all have
/// to agree on which jobs exist, so splitting them would only add ways to drift out of sync.
/// </summary>
public sealed class JobManager : IJobManager
{
    /// <summary>How long a finished job lingers so the UI can animate it out instead of blinking.</summary>
    private static readonly TimeSpan CompletedRetention = TimeSpan.FromSeconds(5);

    private readonly Channel<QueuedJob> _queue =
        Channel.CreateUnbounded<QueuedJob>(new UnboundedChannelOptions { SingleReader = true });

    private readonly ConcurrentDictionary<Guid, JobProgressDto> _jobs = new();
    private readonly ConcurrentDictionary<Guid, CancellationTokenSource> _cancellations = new();
    private readonly ConcurrentDictionary<Guid, Channel<JobProgressDto>> _subscribers = new();

    public ChannelReader<QueuedJob> Reader => _queue.Reader;

    public Guid Enqueue(
        Guid? mediaId,
        string title,
        Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> work)
    {
        var job = new QueuedJob(Guid.NewGuid(), mediaId, title, DateTime.UtcNow, work);

        _cancellations[job.JobId] = new CancellationTokenSource();
        Publish(job, 0, "В очереди", JobStatus.Queued, null);

        if (!_queue.Writer.TryWrite(job))
        {
            _jobs.TryRemove(job.JobId, out _);
            _cancellations.TryRemove(job.JobId, out var source);
            source?.Dispose();
        }

        return job.JobId;
    }

    public IReadOnlyList<JobProgressDto> GetSnapshot() =>
        [.. _jobs.Values.OrderByDescending(job => job.StartedAt)];

    public bool CancelJob(Guid jobId)
    {
        if (!_cancellations.TryGetValue(jobId, out var source))
        {
            return false;
        }

        // Cancel is only a request: the job body decides when it actually unwinds, and the worker
        // publishes the terminal Cancelled state once it does.
        source.Cancel();
        return true;
    }

    public async IAsyncEnumerable<JobProgressDto> SubscribeAsync(
        [EnumeratorCancellation] CancellationToken ct)
    {
        var id = Guid.NewGuid();
        var channel = Channel.CreateBounded<JobProgressDto>(new BoundedChannelOptions(64)
        {
            // A slow reader must not stall the worker; the newest state is the one that matters.
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        });
        _subscribers[id] = channel;

        try
        {
            await foreach (var update in channel.Reader.ReadAllAsync(ct).ConfigureAwait(false))
            {
                yield return update;
            }
        }
        finally
        {
            _subscribers.TryRemove(id, out _);
        }
    }

    /// <summary>
    /// Records the new state and fans it out. Every caller funnels through here, so the snapshot and
    /// the stream can never disagree.
    /// </summary>
    public void Publish(
        QueuedJob job,
        int percent,
        string step,
        JobStatus status,
        string? error,
        CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();

        var update = new JobProgressDto(
            job.JobId,
            job.MediaId,
            job.Title,
            Math.Clamp(percent, 0, 100),
            step,
            status,
            job.StartedAt,
            error);

        _jobs[job.JobId] = update;

        foreach (var subscriber in _subscribers.Values)
        {
            subscriber.Writer.TryWrite(update);
        }
    }

    /// <summary>Drops a job from the registry and frees its cancellation source.</summary>
    public void Forget(Guid jobId)
    {
        _jobs.TryRemove(jobId, out _);
        if (_cancellations.TryRemove(jobId, out var source))
        {
            source.Dispose();
        }
    }

    /// <summary>True when the job is still tracked and has not been cancelled.</summary>
    public bool IsCancellationRequested(Guid jobId) =>
        _cancellations.TryGetValue(jobId, out var source) && source.IsCancellationRequested;

    public CancellationTokenSource CreateRunnerToken(Guid jobId, CancellationToken stoppingToken) =>
        _cancellations.TryGetValue(jobId, out var source)
            ? CancellationTokenSource.CreateLinkedTokenSource(source.Token, stoppingToken)
            : CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);

    /// <summary>
    /// Waits out the retention window, then forgets the job, so the card in the Activity Center
    /// can animate away instead of disappearing the instant it hits 100%.
    /// </summary>
    public async Task ForgetAfterDelayAsync(Guid jobId)
    {
        await Task.Delay(CompletedRetention).ConfigureAwait(false);
        Forget(jobId);
    }
}