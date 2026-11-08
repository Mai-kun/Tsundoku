namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

/// <summary>
/// Shikimori's domain moves regularly (.one, .io, .me, ...), so no base URL is ever stored or
/// hardcoded: the provider keeps the mirror list here, the failover probe promotes whichever
/// mirror answers first, and every URL builder (cover links, the linked-sources panel) reads the
/// active domain at call time instead of baking one in.
/// </summary>
public static class ShikimoriMirrors
{
    /// <summary>Tried in order by the failover walk; the first live one wins.</summary>
    public static readonly string[] Mirrors = ["shikimori.one", "shikimori.io", "shikimori.me"];

    /// <summary>
    /// Live at the time of writing. A wrong guess costs one failed request: the first mirror that
    /// answers becomes active for the rest of the process lifetime.
    /// </summary>
    private static volatile string _active = "shikimori.io";

    public static string ActiveDomain => _active;

    /// <summary>Promotes a mirror; only domains from <see cref="Mirrors"/> are accepted.</summary>
    public static bool SetActive(string domain)
    {
        if (!Mirrors.Contains(domain, StringComparer.OrdinalIgnoreCase))
        {
            return false;
        }

        _active = domain;
        return true;
    }
}
