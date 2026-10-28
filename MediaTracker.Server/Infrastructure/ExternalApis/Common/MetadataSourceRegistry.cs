using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// The single place that knows every external source. Providers declare themselves through a static
/// <see cref="MetadataSourceDescriptor"/>; the <see cref="RegistrationGenerator"/> builds the list of
/// all <c>Provider.Source</c> values at compile time, so no assembly scanning or
/// <see cref="Assembly.GetTypes()"/> is needed at runtime.
/// </summary>
public static partial class MetadataSourceRegistry
{
    private const string DefaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0";

    private static readonly TimeSpan ClientTimeout = TimeSpan.FromSeconds(4);

    /// <summary>All discovered provider descriptors, populated at module initialization by the generator.</summary>
    public static IReadOnlyList<MetadataSourceDescriptor> All => GeneratedSources;

    /// <summary>
    /// Cascade order per media type, lowest <see cref="MetadataSourceDescriptor.Priority"/> first.
    /// Derived, so a new source joins the cascade the moment its file exists.
    /// </summary>
    public static IReadOnlyDictionary<string, string[]> BuildDefaultPriorities()
    {
        var priorities = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);

        foreach (var descriptor in All.OrderBy(s => s.Priority).ThenBy(s => s.Id, StringComparer.Ordinal))
        {
            foreach (var mediaType in descriptor.MediaTypes)
            {
                if (!priorities.TryGetValue(mediaType, out var list))
                {
                    list = [];
                    priorities[mediaType] = list;
                }

                list.Add(descriptor.Id);
            }
        }

        return priorities.ToDictionary(
            entry => entry.Key,
            entry => entry.Value.ToArray(),
            StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>alias -> canonical id, for user input and stored settings that spell it differently.</summary>
    public static IReadOnlyDictionary<string, string> BuildSourceKeyAliases() => BuildLookup(
        (descriptor, map) => map[descriptor.Id] = descriptor.Id);

    /// <summary>alias -> the display name a rating row shows.</summary>
    public static IReadOnlyDictionary<string, string> BuildCanonicalNames() => BuildLookup(
        (descriptor, map) => map[descriptor.Id] = descriptor.RatingSourceName);

    private static IReadOnlyDictionary<string, string> BuildLookup(
        Action<MetadataSourceDescriptor, Dictionary<string, string>> addId)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var descriptor in All)
        {
            addId(descriptor, map);

            foreach (var alias in descriptor.KnownAliases)
            {
                map[alias] = map[descriptor.Id];
            }
        }

        return map;
    }

    /// <summary>
    /// HttpClient name == provider id. Driven by the generated descriptor list instead of reflection.
    /// </summary>
    public static IServiceCollection ConfigureHttpClients(IServiceCollection services)
    {
        // The per-call logger every external client pipes through (see ExternalHttpLoggingHandler).
        services.AddTransient<ExternalHttpLoggingHandler>();

        foreach (var descriptor in All)
        {
            services.AddHttpClient(descriptor.Id, client =>
            {
                client.BaseAddress = new Uri(descriptor.BaseAddress);
                client.Timeout = ClientTimeout;
                client.DefaultRequestHeaders.UserAgent.ParseAdd(descriptor.UserAgent ?? DefaultUserAgent);
            }).AddHttpMessageHandler<ExternalHttpLoggingHandler>();
        }

        // Not a provider: the translation service has its own timeout and no base address.
        services.AddHttpClient("Translation", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(8);
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        }).AddHttpMessageHandler<ExternalHttpLoggingHandler>();

        // Import endpoints (AniList profile / Steam URLs) carry absolute URLs without a base
        // address but go through the same external traffic and the same logging treatment.
        services.AddHttpClient("Import", client => client.Timeout = TimeSpan.FromSeconds(30))
            .AddHttpMessageHandler<ExternalHttpLoggingHandler>();

        return services;
    }

    /// <summary>
    /// Registers every discovered provider with the container. Delegates to the generated
    /// <see cref="AddGeneratedProviders(IServiceCollection)"/> so no <see cref="Assembly.GetTypes()"/>
    /// or <see cref="MethodInfo.MakeGenericMethod(Type[])"/> is needed at runtime.
    /// </summary>
    public static IServiceCollection AddProviders(IServiceCollection services)
    {
        return AddGeneratedProviders(services);
    }
}
