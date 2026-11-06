using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.Rawg;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.Tmdb;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.Translation;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

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

        services.AddSingleton<OfflineDatabaseManager>();
        services.AddSingleton<IMetadataProviderResolver, MetadataProviderResolver>();
        services.AddSingleton<ISourcePriorityService, SourcePriorityService>();

        MetadataSourceRegistry.AddProviders(services);

        services.AddTransient<ITranslationService, TranslationService>();
        // Singleton: the aggregator owns the process-wide in-flight coalescing dictionaries and the
        // IMemoryCache search cache. As a Transient every request built its own instance, so
        // identical parallel searches each paid their own upstream fan-out (AniList quota).
        services.AddSingleton<MetadataAggregatorService>();
        services.AddTransient<RawgGameService>();
        services.AddTransient<TmdbRelationService>();

        return services;
    }
}
