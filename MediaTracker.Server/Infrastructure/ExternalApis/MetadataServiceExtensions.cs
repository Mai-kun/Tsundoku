namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// A metadata source was explicitly requested but could not be reached. Distinct from a
/// generic failure so the API can answer 502 instead of 500 — the client did nothing wrong,
/// the upstream provider is unavailable.
/// </summary>
public sealed class SourceUnavailableException(string source, string reason, Exception? innerException = null)
    : Exception($"Source '{source}' is unavailable: {reason}", innerException)
{
    public string SourceId { get; } = source;
}

public static class MetadataServiceExtensions
{
    /// <summary>
    /// Registers every external source. The provider types are discovered by reflecting over the
    /// assembly for <see cref="IMetadataProvider"/> implementations, and each one's declared
    /// <see cref="MetadataSourceDescriptor"/> drives its named HttpClient, its keyed registrations,
    /// the per-type cascade and the alias tables. Adding a source is therefore one new file.
    /// </summary>
    public static IServiceCollection AddAllMetadataProviders(this IServiceCollection services)
    {
        MetadataSourceRegistry.ConfigureHttpClients(services);

        services.AddSingleton<IMetadataProviderResolver, MetadataProviderResolver>();
        services.AddSingleton<ISourcePriorityService, SourcePriorityService>();

        MetadataSourceRegistry.AddProviders(services);

        services.AddTransient<ITranslationService, TranslationService>();
        services.AddTransient<MetadataAggregatorService>();
        services.AddTransient<RawgGameService>();
        services.AddTransient<TmdbRelationService>();

        return services;
    }
}
