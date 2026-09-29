namespace MediaTracker.Server.Services.External;

public static class MetadataServiceExtensions
{
    private const string DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0";
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(4);
    private static readonly TimeSpan TranslationTimeout = TimeSpan.FromSeconds(8);

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

        services.AddHttpClient("Translation", client =>
        {
            client.Timeout = TranslationTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36");
        });

        return services;
    }

    public static IServiceCollection AddMetadataProviders(this IServiceCollection services)
    {
        RegisterProvider<AniListMetadataProvider>(services, "anilist", ["anime", "manga"], isDefault: true);
        RegisterProvider<JikanMetadataProvider>(services, "jikan", ["anime", "manga"]);
        RegisterProvider<KitsuMetadataProvider>(services, "kitsu", ["anime"]);
        RegisterProvider<MangaDexMetadataProvider>(services, "mangadex", ["manga"]);
        RegisterProvider<MangaUpdatesMetadataProvider>(services, "mangaupdates", ["manga"]);
        RegisterProvider<OpenLibraryMetadataProvider>(services, "openlibrary", ["book"], isDefault: true);
        RegisterProvider<RawgMetadataProvider>(services, "rawg", ["game"], isDefault: true);
        RegisterProvider<TmdbMetadataProvider>(services, "tmdb", ["movie", "tvshow"], isDefault: true);

        services.AddTransient<ITranslationService, TranslationService>();
        services.AddTransient<MetadataAggregatorService>();

        return services;
    }

    private static void RegisterProvider<TProvider>(
        IServiceCollection services,
        string id,
        string[] mediaTypes,
        bool isDefault = false)
        where TProvider : class, IMetadataProvider
    {
        services.AddTransient<IMetadataProvider, TProvider>();
        services.AddKeyedTransient<IMetadataProvider, TProvider>(id);

        foreach (var mediaType in mediaTypes)
        {
            services.AddKeyedTransient<IMetadataProvider, TProvider>($"{mediaType}:{id}");

            if (isDefault)
            {
                services.AddKeyedTransient<IMetadataProvider, TProvider>(mediaType);
            }
        }
    }
}
