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

        services.AddHttpClient("Shikimori", client =>
        {
            client.BaseAddress = new Uri("https://shikimori.io/api/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd("MediaTracker/1.0 (Tsundoku)");
        });

        services.AddHttpClient("GoogleBooks", client =>
        {
            client.BaseAddress = new Uri("https://www.googleapis.com/books/v1/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Steam", client =>
        {
            client.BaseAddress = new Uri("https://store.steampowered.com/api/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Imdb", client =>
        {
            client.BaseAddress = new Uri("https://v2.sg.media-imdb.com/suggestion/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Simkl", client =>
        {
            client.BaseAddress = new Uri("https://api.simkl.com/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd("MediaTracker/1.0");
        });

        services.AddHttpClient("TheTVDB", client =>
        {
            client.BaseAddress = new Uri("https://api4.thetvdb.com/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("Kinopoisk", client =>
        {
            client.BaseAddress = new Uri("https://kinopoiskapiunofficial.tech/api/");
            client.Timeout = DefaultTimeout;
            client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
        });

        services.AddHttpClient("IGDB", client =>
        {
            client.BaseAddress = new Uri("https://api.igdb.com/");
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
        services.AddSingleton<IMetadataProviderResolver, MetadataProviderResolver>();
        services.AddSingleton<ISourcePriorityService, SourcePriorityService>();

        RegisterProvider<AniListMetadataProvider>(services, "anilist", ["anime", "manga"], isDefault: true);
        RegisterProvider<JikanMetadataProvider>(services, "jikan", ["anime", "manga"]);
        RegisterProvider<KitsuMetadataProvider>(services, "kitsu", ["anime"]);
        RegisterProvider<MangaDexMetadataProvider>(services, "mangadex", ["manga"]);
        RegisterProvider<MangaUpdatesMetadataProvider>(services, "mangaupdates", ["manga"]);
        RegisterProvider<OpenLibraryMetadataProvider>(services, "openlibrary", ["book"], isDefault: true);
        RegisterProvider<RawgMetadataProvider>(services, "rawg", ["game"], isDefault: true);
        RegisterProvider<TmdbMetadataProvider>(services, "tmdb", ["movie", "tvshow"], isDefault: true);

        RegisterProvider<ShikimoriMetadataProvider>(services, "shikimori", ["anime", "manga"]);
        RegisterProvider<GoogleBooksMetadataProvider>(services, "googlebooks", ["book"]);
        RegisterProvider<SteamMetadataProvider>(services, "steam", ["game"]);
        RegisterProvider<ImdbMetadataProvider>(services, "imdb", ["movie", "tvshow"]);
        RegisterProvider<SimklMetadataProvider>(services, "simkl", ["anime", "movie", "tvshow"]);
        RegisterProvider<TvdbMetadataProvider>(services, "thetvdb", ["tvshow", "movie"]);
        RegisterProvider<KinopoiskMetadataProvider>(services, "kinopoisk", ["movie", "tvshow"]);
        RegisterProvider<IgdbMetadataProvider>(services, "igdb", ["game"]);

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
