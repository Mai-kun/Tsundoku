using System.Collections.Concurrent;
using System.Reflection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// Base for every provider: the six descriptive properties are read straight off the type's
/// <c>static MetadataSourceDescriptor Source</c>, so a provider declares its own metadata once instead
/// of restating it as instance members that could disagree with it.
/// </summary>
/// <remarks>
/// The descriptor is a static member rather than a static abstract interface member because
/// <c>static abstract</c> makes <see cref="IMetadataProvider"/> unusable as a minimal-API service
/// parameter, which is how SettingsEndpoints enumerates the sources for the settings UI.
/// </remarks>
public abstract class MetadataProviderBase : IMetadataProvider
{
    // One reflection read per provider type, not per instance: keyed DI builds a fresh transient for
    // every resolve, so this sits on the hot path of both search and details.
    private static readonly ConcurrentDictionary<Type, MetadataSourceDescriptor> Cache = new();

    private static MetadataSourceDescriptor SourceOf(Type type) =>
        Cache.GetOrAdd(type, t => (MetadataSourceDescriptor)t
            .GetProperty("Source", BindingFlags.Public | BindingFlags.Static)!
            .GetValue(null)!);

    private MetadataSourceDescriptor Source => SourceOf(GetType());

    public string Id => Source.Id;
    public string Name => Source.Name;
    public string Description => Source.Description;
    public IReadOnlyList<string> MediaTypes => Source.MediaTypes;
    public bool RequiresApiKey => Source.RequiresApiKey;
    public bool IsDefault => Source.IsDefault;

    public abstract Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct);
    public abstract Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct);
}
