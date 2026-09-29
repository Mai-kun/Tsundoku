using MediaTracker.Server.Services.External;

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
        services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anime");
        services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("manga");
        services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("book");
        services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("movie");
        services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tvshow");
        services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("game");

        services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anime:anilist");
        services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("anime:jikan");

        services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("manga:anilist");
        services.AddKeyedTransient<IMetadataProvider, MangaDexMetadataProvider>("manga:mangadex");
        services.AddKeyedTransient<IMetadataProvider, MangaUpdatesMetadataProvider>("manga:mangaupdates");
        services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("manga:jikan");

        services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("book:openlibrary");

        services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("movie:tmdb");

        services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tvshow:tmdb");

        services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("gme:rawg");

        services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anilist");
        services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("jikan");
        services.AddKeyedTransient<IMetadataProvider, MangaDexMetadataProvider>("mangadex");
        services.AddKeyedTransient<IMetadataProvider, MangaUpdatesMetadataProvider>("mangaupdates");
        services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("openlibrary");
        services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tmdb");
        services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("rawg");

        services.AddTransient<MetadataAggregatorService>();

        return services;
    }
}
