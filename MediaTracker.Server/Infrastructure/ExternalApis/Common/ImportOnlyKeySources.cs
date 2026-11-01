namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// Sources that consume a credential only during media import (no metadata
/// provider is registered for them, so they never appear in the sources list).
/// MangaLib authenticates with a user Bearer token captured by the desktop
/// shell; the same save/load pipeline as provider keys applies to it.
/// </summary>
public static class ImportOnlyKeySources
{
    public const string MangaLib = "mangalib";

    private static readonly HashSet<string> Known = new(StringComparer.OrdinalIgnoreCase)
    {
        MangaLib,
    };

    public static bool AcceptsKey(string sourceId) => Known.Contains(sourceId.Trim());
}
