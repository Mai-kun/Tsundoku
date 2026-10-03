using MediaTracker.Server.Features;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Persistence.Interceptors;
using MediaTracker.Server.Infrastructure.Security;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;

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
        services.AddDbContext<AppDbContext>(options =>
            options
                .UseSqlite(connectionString)
                .AddInterceptors(new SqliteConnectionInterceptor()));

        services.AddFeatures();

        services.AddOptions<ExternalApiOptions>();
        // Scoped, not singleton: it takes the scoped AppDbContext, and the only caller resolves it
        // from a scope in InitializeDatabaseAsync. As a singleton it failed DI validation in Development.
        services.AddScoped<StoredSettingsLoader>();

        // Reflection-based: every IMetadataProvider in the assembly registers itself.
        services.AddAllMetadataProviders();

        services.AddSingleton<IEncryptionService, EncryptionService>();
        services.AddSingleton<IFranchiseService, FranchiseService>();

        // Singleton on both halves: the manager owns the queue the worker drains and the registry
        // both read, so a second instance would strand jobs in a channel nobody listens to.
        services.AddSingleton<JobManager>();
        services.AddSingleton<IJobManager>(services => services.GetRequiredService<JobManager>());
        services.AddHostedService<JobWorkerService>();

        services.AddHttpClient<IImageStorageService, ImageStorageService>(client =>
            client.Timeout = TimeSpan.FromSeconds(5));

        return services;
    }
}
