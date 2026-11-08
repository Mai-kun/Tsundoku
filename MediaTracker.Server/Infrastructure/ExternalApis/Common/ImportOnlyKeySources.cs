namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

/// <summary>
/// Sources that consume a credential only during media import (no metadata
/// provider is registered for them, so they never appear in the sources list).
/// MangaLib authenticates with a user Bearer token captured by the desktop
/// shell; the same save/load pipeline as provider keys applies to it.
/// Simkl's session token is the second shape: it rides <em>on top of</em> the
/// provider's client_id (Simkl Auth V2 requires both on user-data requests), so
/// it cannot reuse the provider's own ApiKey_simkl slot without 412-ing the
/// client_id check on every call.
/// </summary>
public static class ImportOnlyKeySources
{
    public const string MangaLib = "mangalib";
    public const string SimklSession = "simkl_session";

    private static readonly HashSet<string> Known = new(StringComparer.OrdinalIgnoreCase)
    {
        MangaLib,
        SimklSession,
    };

    public static bool AcceptsKey(string sourceId) => Known.Contains(sourceId.Trim());
}
