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
#if DEBUG
using OpenApiUi;
#endif
using Serilog;
using Serilog.Events;

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
    return RefactorSelfCheck.Run() == 0 ? 0 : 1;
}

if (options.Mode == TsundokuRunMode.GuiOnly)
{
    Log.Information(
        "Tsundoku starting in client-only mode. Server address: {ServerAddress}",
        options.ServerUrl
    );
    RunPhotinoWindow(options.ServerUrl!);
    Log.CloseAndFlush();
    return 0;
}

var isContainer = CommandLineOptions.IsRunningInContainer;

var appPaths = new AppPaths(
    options.DataDirectory is { Length: > 0 } dataDirectory ? Path.GetFullPath(dataDirectory)
    : isContainer ? Directory.GetCurrentDirectory()
    : Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Tsundoku"
    )
);

ConfigureLogging(appPaths.LogsDirectory);

try
{
    var builder = WebApplication.CreateBuilder();

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
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = embeddedProvider });

    app.UseStaticFiles(
        new StaticFileOptions
        {
            FileProvider = embeddedProvider,
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

        var indexFile = embeddedProvider.GetFileInfo("index.html");
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
        await app.RunAsync();
    }
    else
    {
        await app.StartAsync();
        RunPhotinoWindow(options.ServerUrl!);
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

    var existingLogs = Directory
        .GetFiles(logsDirectory, "session_*.log")
        .Select(f => new FileInfo(f))
        .OrderByDescending(f => f.CreationTimeUtc)
        .ToList();

    if (existingLogs.Count >= 5)
    {
        foreach (var file in existingLogs.Skip(4))
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

static async Task InitializeDatabaseAsync(WebApplication app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();

    await scope.ServiceProvider.GetRequiredService<StoredSettingsLoader>().LoadAsync();

    var franchiseService = scope.ServiceProvider.GetRequiredService<IFranchiseService>();
    await franchiseService.AutoBackfillFranchisesAsync(db);
}

static void RunPhotinoWindow(string serverUrl)
{
    // Photino reads this before the WebView2 controller is created, so it has to be set here rather
    // than on the window: without it the surface flashes white before the web content paints.
    // The value is the UI's --color-canvas (#0d0f14) in WebView2's AARRGGBB form.
    Environment.SetEnvironmentVariable("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "FF0D0F14");

    var uiThread = new Thread(() =>
    {
        var window = new Photino.NET.PhotinoWindow()
            .SetTitle("Tsundoku")
            .SetUseOsDefaultSize(false)
            .SetSize(1300, 850)
            .Center()
            .SetDevToolsEnabled(true)
            .Load(serverUrl);

        window.WaitForClose();
    });

#pragma warning disable CA1416
    uiThread.SetApartmentState(ApartmentState.STA);
#pragma warning restore CA1416
    uiThread.Start();
    uiThread.Join();
}
