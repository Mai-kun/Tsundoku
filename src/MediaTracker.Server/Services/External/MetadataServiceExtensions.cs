namespace MediaTracker.Server.Services.External;

public static class MetadataServiceExtensions
{
    private const string DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0";
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(4);

    public static IServiceCollection AddMetadataHttpClients(this IServiceCollection services)
    {
        services.AddHttpClient("AniList", client =>
        {
            client.BaseAddress = new Uri("https://graphql.anilist.co/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Kitsu", client =>
        {
            client.BaseAddress = new Uri("https://kitsu.io/api/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("OpenLibrary", client =>
        {
            client.BaseAddress = new Uri("https://openlibrary.org/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Tmdb", client =>
        {
            client.BaseAddress = new Uri("https://api.themoviedb.org/3/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Rawg", client =>
        {
            client.BaseAddress = new Uri("https://api.rawg.io/api/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Jikan", client =>
        {
            client.BaseAddress = new Uri("https://api.jikan.moe/v4/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("MangaUpdates", client =>
        {
            client.BaseAddress = new Uri("https://api.mangaupdates.com/v1/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("MangaDex", client =>
        {
            client.BaseAddress = new Uri("https://api.mangadex.org/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        return services;
    }

    public static IServiceCollection AddMetadataProviders(this IServiceCollection services)
    {
        var providerTypes = typeof(IMetadataProvider).Assembly.GetTypes()
            .Where(t => t is { IsClass: true, IsAbstract: false } && typeof(IMetadataProvider).IsAssignableFrom(t));

        foreach (var type in providerTypes)
        {
            var provider = CreatePrototype(type);
            if (provider is null) continue;

            services.AddTransient(typeof(IMetadataProvider), type);
            services.AddKeyedTransient(typeof(IMetadataProvider), provider.Id, type);

            foreach (var mediaType in provider.MediaTypes)
            {
                services.AddKeyedTransient(typeof(IMetadataProvider), $"{mediaType}:{provider.Id}", type);

                if (provider.IsDefault)
                {
                    services.AddKeyedTransient(typeof(IMetadataProvider), mediaType, type);
                }
            }
        }

        services.AddTransient<MetadataAggregatorService>();

        return services;
    }

    private static IMetadataProvider? CreatePrototype(Type type)
    {
        var ctor = type.GetConstructors().MaxBy(c => c.GetParameters().Length);
        if (ctor is null) return null;

        var parameters = ctor.GetParameters();
        var args = new object?[parameters.Length];
        for (var i = 0; i < parameters.Length; i++)
        {
            args[i] = parameters[i].DefaultValue;
        }

        try
        {
            return (IMetadataProvider)ctor.Invoke(args);
        }
        catch
        {
            return null;
        }
    }
}
