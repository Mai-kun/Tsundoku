namespace MediaTracker.Server.Services.External;

public sealed class ExternalApiOptions
{
    public string TmdbApiKey { get; set; } = string.Empty;

    public string RawgApiKey { get; set; } = string.Empty;
}
