using System.Net;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

/// <summary>
/// The retry loop shared by the refresh/enrichment job paths: HTTP 429 waits for the provider's
/// reset window, a network timeout backs off exponentially. Background work can afford to wait,
/// while a cancelled job still unwinds immediately.
/// </summary>
public static class ExternalApiRetry
{
    public static bool IsRateLimited(Exception exception)
    {
        if (exception is HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests })
        {
            return true;
        }

        return exception is SourceUnavailableException source
            && (source.Message.Contains("429", StringComparison.Ordinal)
                || source.InnerException is HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests });
    }

    public static bool IsTimeout(Exception exception) =>
        exception is TimeoutException or TaskCanceledException
        || exception is SourceUnavailableException { InnerException: TaskCanceledException or TimeoutException };

    /// <summary>
    /// Runs <paramref name="action"/> and retries only rate limits and timeouts. <paramref name="ct"/>
    /// is the per-call budget, so a query timeout that expires the token is not retried forever.
    /// </summary>
    public static async Task<T?> RunAsync<T>(
        Func<CancellationToken, Task<T?>> action,
        RateLimitTracker? rateLimiter,
        string source,
        CancellationToken ct,
        Func<int, Task>? onWait = null,
        int maxAttempts = 4)
        where T : class
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await action(ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception) when (
                attempt < maxAttempts
                && !ct.IsCancellationRequested
                && (IsRateLimited(exception) || IsTimeout(exception)))
            {
                var rateLimited = IsRateLimited(exception);
                var wait = rateLimited
                    ? rateLimiter?.GetStatus(source)?.ResetSecondsRemaining ?? 0
                    : 1 << (attempt - 1);

                if (rateLimited && wait <= 0)
                {
                    wait = 60;
                }

                // A 429 reset can be a whole minute; capping keeps a stuck job from hanging forever.
                wait = Math.Clamp(wait, 1, 120);

                if (onWait is not null)
                {
                    await onWait(wait);
                }

                await Task.Delay(TimeSpan.FromSeconds(wait), ct);
            }
        }
    }
}
