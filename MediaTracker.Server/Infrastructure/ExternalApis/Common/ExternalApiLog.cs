using System.Globalization;
using System.Net;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// The three lines every external call writes. The formats live here instead of being restated per
/// provider, so a session log stays greppable: every [ExternalApi] entry opens with the query, and
/// closes with either an item count and a duration or the status and URL that failed.
/// </summary>
internal static class ExternalApiLog
{
    public static void Querying(ILogger? logger, string provider, string mediaType, string query) =>
        logger?.LogInformation(
            "[ExternalApi] Querying {Provider} ({MediaType}) for '{Query}'...",
            provider,
            mediaType,
            query);

    public static void Returned(ILogger? logger, string provider, int count, long elapsedMs) =>
        logger?.LogInformation(
            "[ExternalApi] {Provider} returned {Count} items in {ElapsedMs}ms",
            provider,
            count,
            elapsedMs);

    public static void Failed(ILogger? logger, string provider, HttpStatusCode? status, string url) =>
        logger?.LogWarning(
            "[ExternalApi] {Provider} failed with status {StatusCode} for URL {Url}",
            provider,
            status is null ? "none" : ((int)status).ToString(CultureInfo.InvariantCulture),
            url);

    public static void Failed(ILogger? logger, string provider, Exception error, string url) =>
        logger?.LogWarning(
            error,
            "[ExternalApi] {Provider} failed for URL {Url}: {Message}",
            provider,
            url,
            error.Message);
}