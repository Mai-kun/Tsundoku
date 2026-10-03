using System.Reflection;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

/// <summary>
/// The single place that knows every external source. Providers declare themselves through a static
/// <see cref="MetadataSourceDescriptor"/>; this registry discovers them by scanning the assembly and
/// derives the named HttpClient, the keyed DI registrations, the cascade priority list and the alias
/// tables. Adding a source is one new provider file — no hand-maintained list can forget it.
/// </summary>
public static class MetadataSourceRegistry
{
    private const string DefaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0";

    private static readonly TimeSpan ClientTimeout = TimeSpan.FromSeconds(4);

    /// <summary>
    /// Scanned once behind a <see cref="Lazy{T}"/>: this is reflection over the provider assembly, so
    /// it must not run per lookup.
    /// </summary>
    private static readonly Lazy<IReadOnlyList<MetadataSourceDescriptor>> Sources = new(Discover);

    public static IReadOnlyList<MetadataSourceDescriptor> All => Sources.Value;

    private static IEnumerable<Type> DiscoverTypes() =>
        typeof(IMetadataProvider).Assembly
            .GetTypes()
            .Where(t => !t.IsAbstract && !t.IsInterface && typeof(IMetadataProvider).IsAssignableFrom(t));

    private static MetadataSourceDescriptor Describe(Type type) =>
        (MetadataSourceDescriptor)type
            .GetProperty("Source", BindingFlags.Public | BindingFlags.Static)!
            .GetValue(null)!;

    private static IReadOnlyList<MetadataSourceDescriptor> Discover()
    {
        var descriptors = new List<MetadataSourceDescriptor>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var type in DiscoverTypes())
        {
            var descriptor = Describe(type);

            // Ids key the DI registrations, so a duplicate is a hard startup error rather than a
            // source that silently shadows another one depending on scan order.
            if (!seen.Add(descriptor.Id))
            {
                throw new InvalidOperationException(
                    $"Two metadata providers declare the id '{descriptor.Id}'. Ids must be unique.");
            }

            descriptors.Add(descriptor);
        }

        if (descriptors.Count == 0)
        {
            throw new InvalidOperationException("No IMetadataProvider implementations were found.");
        }

        return descriptors;
    }

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
    /// HttpClient name == provider id. The old hand-written names disagreed with the ids in case and
    /// spelling ("Tmdb" vs "tmdb", "TheTVDB" vs "thetvdb"), so every provider carried a literal that
    /// could drift from its own id and quietly get a client with no BaseAddress.
    /// </summary>
    public static IServiceCollection ConfigureHttpClients(IServiceCollection services)
    {
        foreach (var descriptor in All)
        {
            services.AddHttpClient(descriptor.Id, client =>
            {
                client.BaseAddress = new Uri(descriptor.BaseAddress);
                client.Timeout = ClientTimeout;
                client.DefaultRequestHeaders.UserAgent.ParseAdd(descriptor.UserAgent ?? DefaultUserAgent);
            });
        }

        // Not a provider: the translation service has its own timeout and no base address.
        services.AddHttpClient("Translation", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(8);
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        return services;
    }

    public static IServiceCollection AddProviders(IServiceCollection services)
    {
        foreach (var type in DiscoverTypes())
        {
            var descriptor = Describe(type);

            Register(services, type, descriptor.Id);

            foreach (var mediaType in descriptor.MediaTypes)
            {
                Register(services, type, $"{mediaType}:{descriptor.Id}");

                // The bare media type is what the aggregator resolves when the caller names no source.
                if (descriptor.IsDefault)
                {
                    Register(services, type, mediaType);
                }
            }
        }

        return services;
    }

    private static void Register(IServiceCollection services, Type implementationType, string key)
    {
        // The unkeyed registration is what SettingsEndpoints enumerates to list sources in the UI.
        services.AddTransient(typeof(IMetadataProvider), implementationType);

        // Providers are discovered at runtime, but the only public API that binds an implementation
        // *Type* to a service key is the generic AddKeyedTransient<TService, TImpl>. Registering through
        // the container's own descriptor (rather than an ActivatorUtilities factory) is what keeps
        // [ServiceKey] injection working — providers read that key to tell "anime" from "manga".
        RegisterKeyed
            .MakeGenericMethod(typeof(IMetadataProvider), implementationType)
            .Invoke(null, [services, key]);
    }

    private static readonly MethodInfo RegisterKeyed = typeof(ServiceCollectionServiceExtensions)
        .GetMethods(BindingFlags.Public | BindingFlags.Static)
        .Single(method =>
        {
            if (!method.Name.Equals("AddKeyedTransient", StringComparison.Ordinal))
            {
                return false;
            }

            // On the open generic definition the arguments are still generic *parameters*, so they must
            // be matched as parameters — comparing against typeof(IMetadataProvider) never matches.
            var args = method.GetGenericArguments();
            if (args.Length != 2 || !args[0].IsGenericParameter)
            {
                return false;
            }

            var parameters = method.GetParameters();
            return parameters.Length == 2
                && parameters[0].ParameterType == typeof(IServiceCollection)
                && parameters[1].ParameterType == typeof(object);
        });
}
