namespace MediaTracker.Server.Services.External;

/// <summary>
/// Everything the app needs to know about one external source. A provider declares this once and
/// <see cref="MetadataSourceRegistry"/> derives everything else from it: the named HttpClient, the
/// keyed DI registrations, the cascade priority and the alias tables. Adding a source therefore
/// means adding one file, not editing five tables that must agree by hand.
/// </summary>
public sealed record MetadataSourceDescriptor(
    string Id,
    string Name,
    string Description,
    IReadOnlyList<string> MediaTypes,
    string BaseAddress,
    bool RequiresApiKey = false,
    bool IsDefault = false,
    int Priority = int.MaxValue,
    string? CanonicalName = null,
    IReadOnlyList<string>? Aliases = null,
    string? UserAgent = null)
{
    /// <summary>
    /// Display name for a rating row. Usually <see cref="Name"/>, but a provider needs its own when
    /// the settings label carries a qualifier the shorter rating label must not ("MyAnimeList (Jikan)"
    /// in settings, "MyAnimeList" next to a score).
    /// </summary>
    public string RatingSourceName => string.IsNullOrWhiteSpace(CanonicalName) ? Name : CanonicalName;

    public IReadOnlyList<string> KnownAliases => Aliases ?? [];
}