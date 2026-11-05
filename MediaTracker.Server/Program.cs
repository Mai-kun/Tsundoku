using System.Runtime.InteropServices;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Common.Endpoints;
using MediaTracker.Server.Common.Extensions;
using MediaTracker.Server.Common.Middleware;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Features.Media.Calendar;
using MediaTracker.Server.Features.System.Updates;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Desktop;
using MediaTracker.Server.Infrastructure.Logging;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Security;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.SelfChecks;
using Dapper;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.AspNetCore.StaticFiles;

using Microsoft.Extensions.FileProviders;
using Serilog;
using Serilog.Events;
using OpenApiUi;
using Microsoft.OpenApi;

var options = CommandLineOptions.Parse(args);

if (options.ShowHelp)
{
    ConsoleOutput.Attach();
    Console.WriteLine(CommandLineOptions.HelpText);
    return 0;
}

if (options.Error is { } cliError)
{
    ConsoleOutput.Attach();
    Console.Error.WriteLine($"Tsundoku: {cliError}");
    Console.Error.WriteLine("Run Tsundoku.exe --help to see the available options.");
    return 2;
}

// Self-check runs before any host/DB setup so it stays a pure, fast logic check.
if (options.RunSelfCheck)
{
    ConsoleOutput.Attach();
    return await RefactorSelfCheck.Run() == 0 ? 0 : 1;
}

// One Tsundoku per port: a second launch pings the running instance to surface its UI
// and exits immediately (replaces the Tauri single-instance plugin).
SingleInstanceService.EnsureSingleInstance(options);

var isContainer = CommandLineOptions.IsRunningInContainer;

var builder = WebApplication.CreateBuilder();
var isDevelopment = builder.Environment.IsDevelopment() || options.IsDevMode;
if (options.IsDevMode)
{
    builder.Environment.EnvironmentName = Environments.Development;
}

var appPaths = CreateAppPaths(options, isDevelopment);

if (options.ImportOfflineDb)
{
    ConsoleOutput.Attach();
    var dumpPath = options.OfflineDbDumpPath;
    if (string.IsNullOrEmpty(dumpPath))
    {
        var jsonl = Path.Combine(appPaths.OfflineDirectory, "anime-offline-database.jsonl");
        var json = Path.Combine(appPaths.OfflineDirectory, "anime-offline-database.json");
        var appJsonl = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", "anime-offline-database.jsonl");
        var appJson = Path.Combine(AppPaths.GetAppDirectory(), "data", "offline", "anime-offline-database.json");

        if (File.Exists(jsonl)) dumpPath = jsonl;
        else if (File.Exists(json)) dumpPath = json;
        else if (File.Exists(appJsonl)) dumpPath = appJsonl;
        else if (File.Exists(appJson)) dumpPath = appJson;
        else dumpPath = jsonl;
    }

    if (!File.Exists(dumpPath))
    {
        Console.Error.WriteLine($"Tsundoku: Offline anime dump file not found at '{dumpPath}'.");
        Console.Error.WriteLine("Please place 'anime-offline-database.jsonl' in data/offline/ or specify --offline-dump <path>.");
        return 1;
    }

    Console.WriteLine($"Tsundoku: Importing offline anime database from '{dumpPath}'...");
    var importer = new MediaTracker.Server.Infrastructure.ExternalApis.Offline.AnimeOfflineDatabaseImporter();
    var count = await importer.ImportDumpAsync(dumpPath, appPaths.OfflineDatabasePath);
    Console.WriteLine($"Tsundoku: Successfully imported {count:N0} anime titles into '{appPaths.OfflineDatabasePath}'.");
    return 0;
}

var fileLockGuard = new FileLockGuard(appPaths);
appPaths.LockGuard = fileLockGuard;

// Links for the tray menu, the launcher and /api/system/* endpoints. The server binds
// 0.0.0.0 but the desktop UI is always reached over loopback.
var links = new DesktopLinks(
    UiUrl: $"http://127.0.0.1:{options.EffectivePort}",
    LogsUrl: $"http://127.0.0.1:{options.EffectivePort}/logs.html");

// Desktop shell: tray icon + automatic browser window, unless running as a service.
var enableDesktopShell = !options.IsHeadless && !isContainer;
if (enableDesktopShell)
{
    builder.Services.AddSingleton(options);
    builder.Services.AddSingleton(links);
    builder.Services.AddHostedService<TrayBackgroundService>();
}

// Clean up old binaries
string[] oldBinaries = { "Tsundoku.old", "Tsundoku.exe.old" };
foreach (var oldBinary in oldBinaries)
{
    try
    {
        var path = Path.Combine(AppContext.BaseDirectory, oldBinary);
        if (File.Exists(path)) File.Delete(path);
    }
    catch { /* Ignore */ }
}

ConfigureLogging(appPaths.LogsDirectory);

// Last-resort crash logging: a TypeInitializationException or any other fatal escape used to kill
// the process silently (no window, no log line) and looked like "the backend just vanished".
// The handler cannot save the process, but the log keeps the stack trace for diagnosis.
AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) =>
{
    if (eventArgs.ExceptionObject is Exception ex)
    {
        Log.Fatal(ex, "Unhandled exception. IsTerminating: {IsTerminating}", eventArgs.IsTerminating);
    }
    else
    {
        Log.Fatal("Unhandled non-exception failure. IsTerminating: {IsTerminating}", eventArgs.IsTerminating);
    }
    Log.CloseAndFlush();
};
TaskScheduler.UnobservedTaskException += (_, eventArgs) =>
{
    Log.Warning(eventArgs.Exception, "Unobserved task exception");

    // Mark observed so the task stays swallowed; default .NET behavior keeps the process alive either way.
    eventArgs.SetObserved();
};

Log.Information("Database path: {DatabasePath}", appPaths.DatabaseFilePath);

try
{
    builder.Services.AddHttpClient("steam", client => client.Timeout = TimeSpan.FromSeconds(30))
        .AddHttpMessageHandler<ExternalHttpLoggingHandler>();

    builder.Host.UseSerilog();

    var listenUrl = options.Port is { } kestrelPort
        ? $"http://0.0.0.0:{kestrelPort}"
        : Environment.GetEnvironmentVariable("ASPNETCORE_URLS")
            ?? $"http://0.0.0.0:{CommandLineOptions.DefaultPort}";

    builder.WebHost.UseUrls(listenUrl);

    // Storage-mode changes and tray exit must restart/quit in 1-2 seconds: long-lived SSE
    // connections and background workers should not hold the port during graceful shutdown.
    builder.Services.Configure<HostOptions>(o => o.ShutdownTimeout = TimeSpan.FromSeconds(1.5));

    builder.Services.AddSingleton(appPaths);
    builder.Services.AddSingleton(fileLockGuard);
    builder.Services.AddScoped<IUpdateService, UpdateService>();

    var seedCandidates = new[]
    {
        Path.Combine(AppContext.BaseDirectory, "seed.db"),
        Path.Combine(AppContext.BaseDirectory, "tracker.seed.db"),
        Path.Combine(AppContext.BaseDirectory, "tracker.release.db"),
        "/usr/share/tsundoku/seed.db"
    };
    var seedPath = seedCandidates.FirstOrDefault(File.Exists);
    if (!File.Exists(appPaths.DatabaseFilePath) && seedPath != null)
    {
        Log.Information("Initializing database from seed: {SeedPath} -> {TargetPath}", seedPath, appPaths.DatabaseFilePath);
        File.Copy(seedPath, appPaths.DatabaseFilePath, overwrite: false);
    }

    var connectionString = isContainer
        ? builder.Configuration.GetConnectionString("DefaultConnection")
            ?? $"Data Source={appPaths.DatabaseFilePath}"
        : $"Data Source={appPaths.DatabaseFilePath}";

    builder.Services.AddTsundoku(connectionString);

    builder.Services.ConfigureHttpJsonOptions(options =>
    {
        options.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
        // Reflection-free metadata first; the reflection resolver stays as a fallback.
        options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonSerializerContext.Default);
    });

    builder.Services.AddOpenApi(options =>
    {
        options.AddDocumentTransformer((document, context, cancellationToken) =>
        {
            document.Info ??= new OpenApiInfo();
            document.Info.Title = "Tsundoku API";
            document.Info.Version = "v1";
            document.Info.Description = "Персональный автономный REST API для управления медиатекой (книги, манга, аниме, фильмы, сериалы, игры), интеграций с Home Assistant, ботами и скриптами автоматизации. Поддерживает Bearer/X-Api-Key авторизацию.";

            document.Components ??= new OpenApiComponents();
            document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();

            var bearerScheme = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "Token",
                Description = "Enter your API token (tsk_live_...)"
            };

            var apiKeyScheme = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.ApiKey,
                Name = "X-Api-Key",
                In = ParameterLocation.Header,
                Description = "Enter your API token in the X-Api-Key header"
            };

            document.Components.SecuritySchemes["Bearer"] = bearerScheme;
            document.Components.SecuritySchemes["ApiKey"] = apiKeyScheme;

            return Task.CompletedTask;
        });
    });

    builder.Services.AddProblemDetails();
    builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

    builder.Services.AddResponseCompression(options =>
    {
        // JSON lists dominate the payload on a phone over Wi-Fi; Brotli/Gzip cuts them roughly 5-8x.
        options.EnableForHttps = true;
        options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat([
            "application/json",
            "application/problem+json",
            "image/svg+xml",
        ]);
    });

    builder.Services.AddCors(options =>
    {
        options.AddPolicy(
            "DevCorsPolicy",
            policy =>
            {
                policy.SetIsOriginAllowed(_ => true).AllowAnyHeader().AllowAnyMethod();
            }
        );
    });

    builder.Services.AddMemoryCache();

    var app = builder.Build();

    app.UseSerilogRequestLogging(options =>
    {
        options.GetLevel = (httpContext, elapsed, ex) =>
        {
            if (ex != null || httpContext.Response.StatusCode >= 500)
                return Serilog.Events.LogEventLevel.Error;

            var path = httpContext.Request.Path.Value ?? string.Empty;
            if (path.StartsWith("/api/logs", StringComparison.OrdinalIgnoreCase) ||
                path.StartsWith("/api/jobs/stream", StringComparison.OrdinalIgnoreCase))
            {
                return Serilog.Events.LogEventLevel.Verbose; // Filtered out because min level is Information
            }

            return Serilog.Events.LogEventLevel.Information;
        };
    });

    app.UseResponseCompression();

    await InitializeDatabaseAsync(app);
    await BrowserLauncher.InitializeAsync(app.Services, app.Lifetime);

    if (options.MigrateOnly)
    {
        Log.Information("Database migrations applied. Exiting because of --migrate-only.");
        return 0;
    }

    app.UseExceptionHandler();

    app.UseCors("DevCorsPolicy");

    app.MapOpenApi();
    app.UseOpenApiUi(config => config.OpenApiSpecPath = "/openapi/v1.json");
    app.MapGet("/api/docs", () => Results.Redirect("/openapi-ui")).ExcludeFromDescription();

    var wwwrootCandidates = new[]
    {
        // 1. Режим разработки (dotnet run): папка фронтенда внутри репозитория
        Path.Combine(builder.Environment.ContentRootPath, "wwwroot"),
        Path.Combine(builder.Environment.ContentRootPath, "MediaTracker.Server", "wwwroot"),

        // 2. Портативный запуск рядом с бинарником (для архивов, папки dist и Docker /app/wwwroot)
        Path.Combine(AppContext.BaseDirectory, "wwwroot"),

        // 3. Системный стандарт Linux (для будущих пакетов AUR / pacman / deb / rpm)
        "/usr/share/tsundoku/wwwroot",
        "/usr/lib/tsundoku/wwwroot",

        // 4. Пользовательский оверрайд тем (бонус для кастомизации)
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku", "custom-wwwroot")
    };

    var wwwrootPath = wwwrootCandidates.FirstOrDefault(Directory.Exists)
        ?? Path.Combine(AppContext.BaseDirectory, "wwwroot");

    Directory.CreateDirectory(wwwrootPath);
    Log.Information("Static files path: {StaticFilesPath}", wwwrootPath);
    IFileProvider staticFileProvider = new PhysicalFileProvider(wwwrootPath);

    var contentTypeProvider = new FileExtensionContentTypeProvider();
    contentTypeProvider.Mappings[".webmanifest"] = "application/manifest+json";

    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = staticFileProvider });

    app.UseStaticFiles(
        new StaticFileOptions
        {
            FileProvider = staticFileProvider,
            ContentTypeProvider = contentTypeProvider,
            OnPrepareResponse = context =>
            {
                // Vite emits content-hashed filenames under /assets, so those are immutable exactly like
                // the covers. index.html and diag.html must stay revalidated or a deploy never lands.
                if (context.File.Name.EndsWith(".html", StringComparison.OrdinalIgnoreCase)
                    || context.File.Name.EndsWith(".webmanifest", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(context.File.Name, "sw.js", StringComparison.OrdinalIgnoreCase))
                {
                    context.Context.Response.Headers.CacheControl = "no-cache";
                }
                else
                {
                    context.Context.Response.Headers.CacheControl =
                        "public, max-age=31536000, immutable";
                }
            },
        }
    );

    // Per-title assets: data/media/{mediaId}/cover/{original,thumb}.webp. Legacy /covers stays mounted
    // below so rows saved before this layout keep resolving their stored URL.
    app.UseStaticFiles(
        new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(appPaths.MediaDirectory),
            RequestPath = "/media-assets",
            OnPrepareResponse = context =>
                context.Context.Response.Headers.CacheControl =
                    "public, max-age=31536000, immutable",
        }
    );

    app.UseStaticFiles(
        new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(appPaths.CoversDirectory),
            RequestPath = "/covers",
            OnPrepareResponse = context =>
                context.Context.Response.Headers.CacheControl =
                    "public, max-age=31536000, immutable",
        }
    );

    app.UseMiddleware<ApiKeyAuthMiddleware>();

    app.MapMediaEndpoints();
    app.MapListEndpoints();
    app.MapSeasonEndpoints();
    app.MapExternalMediaEndpoints();
    app.MapLogEndpoints();
    app.MapSettingsEndpoints();
    app.MapJobEndpoints();
    app.MapCalendarEndpoints();
    app.MapGoalEndpoints();
    app.MapSystemEndpoints(links, appPaths);

    app.MapFallback(async context =>
    {
        var path = context.Request.Path.Value ?? string.Empty;
        if (path.StartsWith("/api", StringComparison.OrdinalIgnoreCase))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        var indexFile = staticFileProvider.GetFileInfo("index.html");
        if (!indexFile.Exists)
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
        }

        context.Response.StatusCode = StatusCodes.Status200OK;
        context.Response.ContentType = "text/html; charset=utf-8";
        context.Response.Headers.CacheControl = "no-cache";
        await using var stream = indexFile.CreateReadStream();
        await stream.CopyToAsync(context.Response.Body);
    });

    Log.Information(
        "Tsundoku starting. .NET Version: {DotNetVersion}, OS: {OSDescription}, Server Address: {ServerAddress}, Shell: {ShellMode}",
        Environment.Version.ToString(),
        RuntimeInformation.OSDescription,
        listenUrl,
        enableDesktopShell ? "desktop (tray + browser)" : "headless");

    // Headless Kestrel service: kick off the backfill concurrently instead of blocking startup.
    StartBackgroundFranchiseBackfill(app);
    StartBackgroundOfflineDatabaseImports(app);

    if (enableDesktopShell && !options.StartMinimized)
    {
        // Surface the UI as soon as Kestrel accepts connections (replaces the Tauri
        // startup path that opened the browser once the server port was ready).
        app.Lifetime.ApplicationStarted.Register(() => BrowserLauncher.OpenUrl(links.UiUrl));
    }

    app.Lifetime.ApplicationStopping.Register(() => fileLockGuard.Dispose());

    await app.RunAsync();
}
finally
{
    fileLockGuard.Dispose();
    Log.CloseAndFlush();
    SingleInstanceService.ReleaseLock();
}

if (AppRestartService.IsRestartScheduled)
{
    AppRestartService.ExecuteRestart();
}

return 0;

static void ConfigureLogging(string logsDirectory)
{
    Directory.CreateDirectory(logsDirectory);

    // Fast count check before materializing FileInfo for every log file on disk.
    var logFiles = Directory.GetFiles(logsDirectory, "session_*.log");
    if (logFiles.Length >= 5)
    {
        var filesToDelete = logFiles
            .Select(f => new FileInfo(f))
            .OrderByDescending(f => f.CreationTimeUtc)
            .Skip(4);

        foreach (var file in filesToDelete)
        {
            try
            {
                file.Delete();
            }
            catch
            {
                // ignored
            }
        }
    }

    var currentSessionLogFile = Path.Combine(
        logsDirectory,
        $"session_{DateTime.UtcNow:yyyy-MM-dd_HH-mm-ss}.log"
    );

    const string outputTemplate =
        "[{Timestamp:yyyy-MM-dd HH:mm:ss.fff}] [{Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Exception}";

    Log.Logger = new LoggerConfiguration()
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
        .MinimumLevel.Override("System", LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.EntityFrameworkCore", LogEventLevel.Warning)
        .Enrich.FromLogContext()
        .WriteTo.Console(outputTemplate: outputTemplate)
        .WriteTo.File(path: currentSessionLogFile, outputTemplate: outputTemplate, shared: true)
        .CreateLogger();
}

static AppPaths CreateAppPaths(CommandLineOptions options, bool isDevelopment)
{
    return AppPaths.Create(options, isDevelopment);
}

static async Task InitializeDatabaseAsync(WebApplication app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var appPaths = app.Services.GetRequiredService<AppPaths>();

    // Initialize the schema using Dapper-based initializer (no EF Core migrations).
    Log.Information("Checking and initializing database schema...");
    await db.EnsureSchemaAsync();

    await scope.ServiceProvider.GetRequiredService<StoredSettingsLoader>().LoadAsync();

    // Self-heal at startup: rows parked in Syncing by a cancelled or crashed session (an in-memory
    // job queue does not survive a restart) would show a forever-spinning "синхронизация" badge.
    var conn = db.Connection;
    if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync();
    await conn.ExecuteAsync(
        "UPDATE MediaItems SET SyncStatus = @ready, UpdatedAt = @now WHERE SyncStatus = @syncing;",
        new { ready = (int)SyncStatus.Ready, syncing = (int)SyncStatus.Syncing, now = DateTime.UtcNow });

    // External cover URLs are kept as the fallback until ImageStorageService successfully downloads
    // and saves a local WebP variant. Nullifying them on startup would wipe covers that can never be
    // restored (offline restart, in-progress import), so this is intentionally not done here.
}

static void StartBackgroundFranchiseBackfill(WebApplication app)
{
    // Fire-and-forget so Kestrel starts listening immediately.
    _ = Task.Run(async () =>
    {
        try
        {
            using var bgScope = app.Services.CreateScope();
            var bgDb = bgScope.ServiceProvider.GetRequiredService<AppDbContext>();
            var bgFranchise = bgScope.ServiceProvider.GetRequiredService<IFranchiseService>();
            await bgFranchise.AutoBackfillFranchisesAsync(bgDb);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Background franchise auto-backfill failed");
        }
    });
}

static void StartBackgroundOfflineDatabaseImports(WebApplication app)
{
    var jobManager = app.Services.GetRequiredService<IJobManager>();
    var dbManager = app.Services.GetRequiredService<MediaTracker.Server.Infrastructure.ExternalApis.Offline.OfflineDatabaseManager>();
    dbManager.EnqueuePendingImports(jobManager, app.Logger);
}
