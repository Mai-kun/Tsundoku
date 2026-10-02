namespace MediaTracker.Server.Services.External;

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
    public static IServiceCollection AddMetadataHttpClients(this IServiceCollection services) =>
        MetadataSourceRegistry.ConfigureHttpClients(services);

    public static IServiceCollection AddMetadataProviders(this IServiceCollection services)
    {
        services.AddSingleton<IMetadataProviderResolver, MetadataProviderResolver>();
        services.AddSingleton<ISourcePriorityService, SourcePriorityService>();

        MetadataSourceRegistry.AddProviders(services);

        services.AddTransient<ITranslationService, TranslationService>();
        services.AddTransient<MetadataAggregatorService>();
        services.AddTransient<RawgGameService>();

        return services;
    }
}
