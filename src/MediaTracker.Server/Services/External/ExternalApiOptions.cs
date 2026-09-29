namespace MediaTracker.Server.Services.External;

public sealed class ExternalApiOptions
{
    public string TmdbApiKey { get; set; } = string.Empty;
    public string RawgApiKey { get; set; } = string.Empty;
    public string GoogleBooksApiKey { get; set; } = string.Empty;
    public string SimklApiKey { get; set; } = string.Empty;
    public string TvdbApiKey { get; set; } = string.Empty;
    public string KinopoiskApiKey { get; set; } = string.Empty;
    public string IgdbApiKey { get; set; } = string.Empty;

    private readonly Dictionary<string, string> _customKeys = new(StringComparer.OrdinalIgnoreCase);

    public string? GetKey(string sourceId)
    {
        var id = sourceId.Trim().ToLowerInvariant();
        return id switch
        {
            "tmdb" => TmdbApiKey,
            "rawg" => RawgApiKey,
            "googlebooks" or "google" => GoogleBooksApiKey,
            "simkl" => SimklApiKey,
            "tvdb" or "thetvdb" => TvdbApiKey,
            "kinopoisk" => KinopoiskApiKey,
            "igdb" => IgdbApiKey,
            _ => _customKeys.TryGetValue(id, out var key) ? key : null
        };
    }

    public void SetKey(string sourceId, string key)
    {
        var id = sourceId.Trim().ToLowerInvariant();
        switch (id)
        {
            case "tmdb":
                TmdbApiKey = key;
                break;
            case "rawg":
                RawgApiKey = key;
                break;
            case "googlebooks" or "google":
                GoogleBooksApiKey = key;
                break;
            case "simkl":
                SimklApiKey = key;
                break;
            case "tvdb" or "thetvdb":
                TvdbApiKey = key;
                break;
            case "kinopoisk":
                KinopoiskApiKey = key;
                break;
            case "igdb":
                IgdbApiKey = key;
                break;
            default:
                _customKeys[id] = key;
                break;
        }
    }
}
