namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class ExternalApiOptions
{
    public string TmdbApiKey { get; set; } = string.Empty;
    public string RawgApiKey { get; set; } = string.Empty;
    public string SimklApiKey { get; set; } = string.Empty;
    public string KinopoiskApiKey { get; set; } = string.Empty;
    public string SteamApiKey { get; set; } = string.Empty;

    // OrdinalIgnoreCase already makes the lookup case-insensitive, so no lowercase copy of the id is
    // allocated per call. Left as a plain Dictionary because SetKey mutates it.
    private readonly Dictionary<string, string> _customKeys = new(StringComparer.OrdinalIgnoreCase);

    private static bool Is(string value, string expected) =>
        string.Equals(value, expected, StringComparison.OrdinalIgnoreCase);

    public string? GetKey(string sourceId)
    {
        var id = sourceId.Trim();

        if (Is(id, "tmdb")) return TmdbApiKey;
        if (Is(id, "rawg")) return RawgApiKey;
        if (Is(id, "simkl")) return SimklApiKey;
        if (Is(id, "kinopoisk")) return KinopoiskApiKey;
        if (Is(id, "steam")) return SteamApiKey;

        return _customKeys.TryGetValue(id, out var key) ? key : null;
    }

    public void SetKey(string sourceId, string key)
    {
        var id = sourceId.Trim();

        if (Is(id, "tmdb")) { TmdbApiKey = key; return; }
        if (Is(id, "rawg")) { RawgApiKey = key; return; }
        if (Is(id, "simkl")) { SimklApiKey = key; return; }
        if (Is(id, "kinopoisk")) { KinopoiskApiKey = key; return; }
        if (Is(id, "steam")) { SteamApiKey = key; return; }

        _customKeys[id] = key;
    }

    public void ClearKeys()
    {
        TmdbApiKey = string.Empty;
        RawgApiKey = string.Empty;
        SimklApiKey = string.Empty;
        KinopoiskApiKey = string.Empty;
        SteamApiKey = string.Empty;
        _customKeys.Clear();
    }
}
