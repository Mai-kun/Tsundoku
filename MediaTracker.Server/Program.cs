using System.Runtime.InteropServices;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Common.Endpoints;
using MediaTracker.Server.Common.Extensions;
using MediaTracker.Server.Common.Middleware;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Logging;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Security;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.SelfChecks;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Serilog;
using Serilog.Events;
#if DEBUG
using OpenApiUi;
#endif

if (OperatingSystem.IsLinux())
{
    // Принудительный бэкенд X11/XWayland для стабильности GTK3 и защита от крашей DMA-BUF
    if (
        string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GDK_BACKEND"))
        || string.Equals(
            Environment.GetEnvironmentVariable("GDK_BACKEND"),
            "wayland",
            StringComparison.OrdinalIgnoreCase
        )
    )
    {
        Environment.SetEnvironmentVariable("GDK_BACKEND", "x11");
    }
    if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBKIT_DISABLE_DMABUF_RENDERER")))
    {
        Environment.SetEnvironmentVariable("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
}

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
    return RefactorSelfCheck.Run() == 0 ? 0 : 1;
}

if (options.Mode == TsundokuRunMode.GuiOnly)
{
    var guiPaths = CreateAppPaths(options);
    if (OperatingSystem.IsWindows())
    {
        ConfigureWebView2(guiPaths);
    }
    else
    {
        ConfigureLinuxEnvironment(guiPaths);
    }
    Log.Information(
        "Tsundoku starting in client-only mode. Server address: {ServerAddress}",
        options.ServerUrl
    );
    RunPhotinoWindow(options.ServerUrl!);
    Log.CloseAndFlush();
    return 0;
}

var isContainer = CommandLineOptions.IsRunningInContainer;

var appPaths = CreateAppPaths(options);

if (OperatingSystem.IsWindows() && !options.IsHeadless && !options.MigrateOnly)
{
    ConfigureWebView2(appPaths);
}
else if (!OperatingSystem.IsWindows() && !options.IsHeadless && !options.MigrateOnly)
{
    ConfigureLinuxEnvironment(appPaths);
}

ConfigureLogging(appPaths.LogsDirectory);

try
{
    var builder = WebApplication.CreateBuilder();

    builder.Services.AddHttpClient("steam", client => client.Timeout = TimeSpan.FromSeconds(30));

    builder.Host.UseSerilog();

    var listenUrl = options.Port is { } kestrelPort
        ? $"http://0.0.0.0:{kestrelPort}"
        : Environment.GetEnvironmentVariable("ASPNETCORE_URLS")
            ?? $"http://0.0.0.0:{CommandLineOptions.DefaultPort}";

    builder.WebHost.UseUrls(listenUrl);

    builder.Services.AddSingleton(appPaths);

    var connectionString = isContainer
        ? builder.Configuration.GetConnectionString("DefaultConnection")
            ?? $"Data Source={appPaths.DatabaseFilePath}"
        : $"Data Source={appPaths.DatabaseFilePath}";

    builder.Services.AddTsundoku(connectionString);

    builder.Services.ConfigureHttpJsonOptions(options =>
    {
        options.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
    });

#if DEBUG
    builder.Services.AddOpenApi();
#endif

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
                policy.WithOrigins("http://localhost:5173").AllowAnyHeader().AllowAnyMethod();
            }
        );
    });

    builder.Services.AddMemoryCache();

    var app = builder.Build();

    app.UseSerilogRequestLogging();

    app.UseResponseCompression();

    await InitializeDatabaseAsync(app);

    if (options.MigrateOnly)
    {
        Log.Information("Database migrations applied. Exiting because of --migrate-only.");
        return 0;
    }

    app.UseExceptionHandler();

#if DEBUG
    if (app.Environment.IsDevelopment())
    {
        app.UseCors("DevCorsPolicy");
        app.MapOpenApi();
        app.UseOpenApiUi(config => config.OpenApiSpecPath = "/openapi/v1.json");
    }
#endif

    var embeddedProvider = new ManifestEmbeddedFileProvider(typeof(Program).Assembly, "wwwroot");
    var wwwrootCandidates = new[]
    {
        Path.Combine(builder.Environment.ContentRootPath, "wwwroot"),
        Path.Combine(builder.Environment.ContentRootPath, "MediaTracker.Server", "wwwroot"),
        Path.Combine(AppContext.BaseDirectory, "wwwroot"),
    };
    var wwwrootPath = wwwrootCandidates.FirstOrDefault(Directory.Exists)
        ?? Path.Combine(builder.Environment.ContentRootPath, "wwwroot");
    IFileProvider staticFileProvider = Directory.Exists(wwwrootPath)
        ? new CompositeFileProvider(new PhysicalFileProvider(wwwrootPath), embeddedProvider)
        : embeddedProvider;

    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = staticFileProvider });

    app.UseStaticFiles(
        new StaticFileOptions
        {
            FileProvider = staticFileProvider,
            OnPrepareResponse = context =>
            {
                // Vite emits content-hashed filenames under /assets, so those are immutable exactly like
                // the covers. index.html and diag.html must stay revalidated or a deploy never lands.
                if (context.File.Name.EndsWith(".html", StringComparison.OrdinalIgnoreCase))
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

    app.MapMediaEndpoints();
    app.MapListEndpoints();
    app.MapSeasonEndpoints();
    app.MapExternalMediaEndpoints();
    app.MapLogEndpoints();
    app.MapSettingsEndpoints();
    app.MapJobEndpoints();

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

    var mode = options.Mode == TsundokuRunMode.Headless ? "Headless" : "Photino";
    Log.Information(
        "Tsundoku starting. .NET Version: {DotNetVersion}, OS: {OSDescription}, Mode: {Mode}, Server Address: {ServerAddress}",
        Environment.Version.ToString(),
        RuntimeInformation.OSDescription,
        mode,
        listenUrl
    );

    if (options.IsHeadless)
    {
        // Headless serves forever; kick off the backfill concurrently instead of blocking startup.
        StartBackgroundFranchiseBackfill(app);
        await app.RunAsync();
    }
    else
    {
        await app.StartAsync();

        // Фоновый запуск бэкфилла франшиз без блокировки открытия UI-окна
        StartBackgroundFranchiseBackfill(app);

        try
        {
            RunPhotinoWindow(options.ServerUrl!);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Photino GUI failed to start. Falling back to Headless mode.");
            ConsoleOutput.Attach();
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"[Tsundoku] Не удалось открыть графическое окно Photino: {ex.Message}");
            Console.ResetColor();
            Console.WriteLine($"[Tsundoku] Сервер продолжает работать в штатном фоновом режиме!");
            Console.WriteLine($"[Tsundoku] Откройте приложение в браузере: {options.ServerUrl}");
            Console.WriteLine();

            // Сервер не гасится, а ждет сигнала завершения (Ctrl+C / SIGTERM)
            await app.WaitForShutdownAsync();
            return 0;
        }

        await app.StopAsync();
    }
}
finally
{
    Log.CloseAndFlush();
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

static AppPaths CreateAppPaths(CommandLineOptions options)
{
    var dataDirectory =
        options.DataDirectory is { Length: > 0 } configuredDirectory
            ? Path.GetFullPath(configuredDirectory)
        : CommandLineOptions.IsRunningInContainer ? Directory.GetCurrentDirectory()
        : Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Tsundoku"
        );

    return new AppPaths(dataDirectory);
}

static void ConfigureWebView2(AppPaths appPaths)
{
    var webViewCacheDir = Path.Combine(appPaths.DataDirectory, "cache", "webview2");
    Directory.CreateDirectory(webViewCacheDir);

    Environment.SetEnvironmentVariable(
        "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
        "--enable-gpu-rasterization "
            + "--ignore-gpu-blocklist "
            + "--disable-features=msWebOOUI,msPdfOOUI "
            + "--enable-smooth-scrolling"
    );
    Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", webViewCacheDir);
}

static void ConfigureLinuxEnvironment(AppPaths appPaths)
{
    // Защита от краша "Protocol error dispatching to Wayland display" в WebKitGTK / Photino
    if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GDK_BACKEND")))
    {
        Environment.SetEnvironmentVariable("GDK_BACKEND", "x11");
    }

    if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WEBKIT_DISABLE_DMABUF_RENDERER")))
    {
        Environment.SetEnvironmentVariable("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
}

static async Task InitializeDatabaseAsync(WebApplication app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    // Only run the full migration pipeline when there are actually pending migrations;
    // on an up-to-date database GetPendingMigrationsAsync short-circuits cheaply.
    var pendingMigrations = await db.Database.GetPendingMigrationsAsync();
    if (pendingMigrations.Any())
    {
        Log.Information(
            "Applying {Count} pending database migration(s)...",
            pendingMigrations.Count()
        );
        await db.Database.MigrateAsync();
    }

    await scope.ServiceProvider.GetRequiredService<StoredSettingsLoader>().LoadAsync();
}

static void StartBackgroundFranchiseBackfill(WebApplication app)
{
    // Фоновый запуск бэкфилла франшиз без блокировки открытия UI-окна
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

static void RunPhotinoWindow(string serverUrl)
{
    // Photino reads this before the WebView2 controller is created, so it has to be set here rather
    // than on the window: without it the surface flashes white before the web content paints.
    // The value is the UI's --color-canvas (#0d0f14) in WebView2's AARRGGBB form.
    if (OperatingSystem.IsWindows())
    {
        Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "FF0D0F14");
    }

    Exception? threadException = null;

    var uiThread = new Thread(() =>
    {
        try
        {
            if (OperatingSystem.IsLinux())
            {
                if (
                    string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY"))
                    && string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY"))
                )
                {
                    throw new InvalidOperationException(
                        "No graphical display found (neither DISPLAY nor WAYLAND_DISPLAY is set)."
                    );
                }

                try
                {
                    if (!GtkInitCheck(IntPtr.Zero, IntPtr.Zero))
                    {
                        throw new InvalidOperationException("Cannot open display or initialize GTK3.");
                    }
                }
                catch (DllNotFoundException)
                {
                    throw new InvalidOperationException("GTK3 runtime library (libgtk-3.so.0) not found.");
                }
            }

            var window = new Photino.NET.PhotinoWindow()
                .SetTitle("Tsundoku")
                .SetUseOsDefaultSize(false)
                .SetSize(1300, 850)
                .Center()
                .SetDevToolsEnabled(true)
                .Load(serverUrl);

            window.WaitForClose();
        }
        catch (Exception ex)
        {
            threadException = ex;
        }
    });

#pragma warning disable CA1416
    if (OperatingSystem.IsWindows())
    {
        uiThread.SetApartmentState(ApartmentState.STA);
    }
#pragma warning restore CA1416
    uiThread.Start();
    uiThread.Join();

    if (threadException != null)
    {
        throw threadException;
    }
}

[DllImport("libgtk-3.so.0", EntryPoint = "gtk_init_check")]
[return: MarshalAs(UnmanagedType.Bool)]
static extern bool GtkInitCheck(IntPtr argc, IntPtr argv);
