using MediaTracker.Server.Features;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Security;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Common.Extensions;

/// <summary>
/// Composition helpers used by Program.cs: one call per concern so the entry point stays a sequence of
/// registrations instead of a wall of individual <c>Add*</c> lines.
/// </summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// The whole application surface: persistence, features and the external infrastructure. Called
    /// from Program.cs with the connection string it resolved.
    /// </summary>
    public static IServiceCollection AddTsundoku(
        this IServiceCollection services,
        string connectionString)
    {
        services.AddScoped<AppDbContext>(sp => new AppDbContext(connectionString));

        services.AddFeatures();

        services.AddOptions<ExternalApiOptions>();
        // Scoped, not singleton: it takes the scoped AppDbContext, and the only caller resolves it
        // from a scope in InitializeDatabaseAsync. As a singleton it failed DI validation in Development.
        services.AddScoped<StoredSettingsLoader>();

        // Живой снимок настроек прокси: регистрируется ДО клиентов провайдеров — их primary
        // handlers захватывают IProxySettingsService из контейнера.
        services.AddSingleton<IProxySettingsService, ProxySettingsService>();

        // Живой снимок вынесенных категорий навигации: SQL-фильтры списков и статистики
        // читают его на каждом запросе — сохранение применяется мгновенно.
        services.AddSingleton<
            MediaTracker.Server.Features.Settings.NavigationCategories.INavigationCategoriesService,
            MediaTracker.Server.Features.Settings.NavigationCategories.NavigationCategoriesService>();

        // Reflection-based: every IMetadataProvider in the assembly registers itself.
        services.AddAllMetadataProviders();

        services.AddSingleton<IEncryptionService, EncryptionService>();
        services.AddSingleton<IFranchiseService, FranchiseService>();

        // Singleton on both halves: the manager owns the queue the worker drains and the registry
        // both read, so a second instance would strand jobs in a channel nobody listens to.
        services.AddSingleton<JobManager>();
        services.AddSingleton<IJobManager>(services => services.GetRequiredService<JobManager>());
        services.AddHostedService<JobWorkerService>();
        services.AddHostedService<Features.Jobs.AutoRefreshWorker>();

        services.AddHttpClient<IImageStorageService, ImageStorageService>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(5);
            client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0");
        })
        .ConfigurePrimaryHttpMessageHandler(sp => new SocketsHttpHandler
        {
            // Скачивание обложек: непривязанный клиент — источник определяется по домену CDN
            // (uploads.mangadex.org → mangadex, image.tmdb.org → tmdb, imglib.info → sociallib).
            // Прокси применяется только если источник отмечен в ProxiedSources.
            UseProxy = true,
            Proxy = new DynamicSourceProxy(sp.GetRequiredService<IProxySettingsService>(), null),
        })
        .AddHttpMessageHandler<ExternalHttpLoggingHandler>();

        // The image-proxy endpoint streams covers for the search previews; a slightly larger budget
        // than the cover downloader because the response reaches the browser live.
        services.AddHttpClient("ExternalImageProxy", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(10);
        })
        .ConfigurePrimaryHttpMessageHandler(sp => new SocketsHttpHandler
        {
            // Превью внешнего поиска: та же доменная маршрутизация, что и у скачивания обложек.
            UseProxy = true,
            Proxy = new DynamicSourceProxy(sp.GetRequiredService<IProxySettingsService>(), null),
        });

        services.AddScoped<IBackupService, BackupService>();

        return services;
    }
}
