namespace MediaTracker.Server.Services.External;

public sealed class ExternalApiOptions
{
    public string TmdbApiKey { get; set; } = string.Empty;

    public string RawgApiKey { get; set; } = string.Empty;

    public string? GetKey(string sourceId) => sourceId.ToLowerInvariant() switch
    {
        "tmdb" => TmdbApiKey,
        "rawg" => RawgApiKey,
        _ => null
    };

    public void SetKey(string sourceId, string key)
    {
        switch (sourceId.ToLowerInvariant())
        {
            case "tmdb":
                TmdbApiKey = key;
                break;
            case "rawg":
                RawgApiKey = key;
                break;
        }
    }
}
