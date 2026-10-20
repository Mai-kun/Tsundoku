namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed record ConnectionTestResult(bool Success, int LatencyMs, string Message);

public interface IMetadataProvider
{
    string Id { get; }
    string Name { get; }
    string Description { get; }
    IReadOnlyList<string> MediaTypes { get; }
    bool RequiresApiKey { get; }
    bool IsDefault { get; }

    Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
    Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct);

    /// <summary>
    /// Declared abstract here (not with a default body) so the aggregator can route a creator
    /// search through it: every provider derives from <see cref="MetadataProviderBase"/>, which
    /// supplies the searchable-and-filter default and the AniList/book sources their native
    /// studio/author overrides.
    /// </summary>
    Task<IReadOnlyList<ExternalMediaDto>> SearchByCreatorAsync(string creator, CancellationToken ct);

    /// <summary>
    /// Declared without a default body on purpose. A default interface member is only taken over by a
    /// derived class that re-lists the interface or whose base redeclares it, and this interface is
    /// implemented by the abstract base — so a default here would shadow every provider's own
    /// <c>TestConnectionAsync</c> instead of backing it, and the settings screen would keep running the
    /// generic "search for the word test" probe, which reports OK for a key the provider rejects.
    /// The shared fallback lives on <see cref="MetadataProviderBase"/> as a virtual method.
    /// </summary>
    Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct);
}
