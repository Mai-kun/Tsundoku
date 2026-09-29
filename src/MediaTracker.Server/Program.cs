using System.Runtime.InteropServices;
using System.Text.Json.Serialization;
using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.Endpoints;
using MediaTracker.Server.Infrastructure;
using MediaTracker.Server.Middleware;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Franchises;
using MediaTracker.Server.Services.Security;
using MediaTracker.Server.Services.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using OpenApiUi;
using Serilog;
using Serilog.Events;

var isContainer = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";
var isHeadless = isContainer
                 || args.Contains("--headless")
                 || Environment.GetEnvironmentVariable("HEADLESS") == "true";

var appPaths = new AppPaths(isContainer
    ? Directory.GetCurrentDirectory()
    : Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Tsundoku"));

ConfigureLogging(appPaths.LogsDirectory);

try
{
    var builder = WebApplication.CreateBuilder(args);
    builder.Host.UseSerilog();

    builder.WebHost.UseUrls("http://0.0.0.0:5000");

    builder.Services.AddSingleton(appPaths);

    var connectionString = isContainer
        ? builder.Configuration.GetConnectionString("DefaultConnection")
          ?? $"Data Source={appPaths.DatabaseFilePath}"
        : $"Data Source={appPaths.DatabaseFilePath}";

    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseSqlite(connectionString)
            .AddInterceptors(new SqliteConnectionInterceptor()));

    builder.Services.AddValidatorsFromAssemblyContaining<Program>();

    builder.Services.ConfigureHttpJsonOptions(options =>
    {
        options.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
    });

    builder.Services.AddOpenApi();
    builder.Services.AddProblemDetails();
    builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

    builder.Services.AddCors(options =>
    {
        options.AddPolicy("DevCorsPolicy", policy =>
        {
            policy.WithOrigins("http://localhost:5173")
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        });
    });

    builder.Services.AddMemoryCache();
    builder.Services.AddOptions<ExternalApiOptions>();
    builder.Services.AddSingleton<IEncryptionService, EncryptionService>();
    builder.Services.AddSingleton<IFranchiseService, FranchiseService>();

    builder.Services.AddMetadataHttpClients();
    builder.Services.AddMetadataProviders();

    builder.Services.AddHttpClient<IImageStorageService, ImageStorageService>(client =>
        client.Timeout = TimeSpan.FromSeconds(5));

    var app = builder.Build();

    app.UseSerilogRequestLogging();

    await InitializeDatabaseAsync(app);

    app.UseExceptionHandler();

    if (app.Environment.IsDevelopment())
    {
        app.UseCors("DevCorsPolicy");
        app.MapOpenApi();
        app.UseOpenApiUi(config => config.OpenApiSpecPath = "/openapi/v1.json");
    }

    var embeddedProvider = new ManifestEmbeddedFileProvider(typeof(Program).Assembly, "wwwroot");
    app.UseDefaultFiles(new DefaultFilesOptions
    {
        FileProvider = embeddedProvider
    });

    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = embeddedProvider
    });

    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(appPaths.CoversDirectory),
        RequestPath = "/covers",
        OnPrepareResponse = context => context.Context.Response.Headers.CacheControl = "public, max-age=31536000, immutable"
    });

    app.MapMediaEndpoints();
    app.MapSeasonEndpoints();
    app.MapVolumeEndpoints();
    app.MapExternalMediaEndpoints();
    app.MapLogEndpoints();
    app.MapSettingsEndpoints();

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
        await using var stream = indexFile.CreateReadStream();
        await stream.CopyToAsync(context.Response.Body);
    });

    var mode = isHeadless ? "Headless" : "Photino";
    Log.Information(
        "Tsundoku starting. .NET Version: {DotNetVersion}, OS: {OSDescription}, Mode: {Mode}, Server Address: {ServerAddress}",
        Environment.Version.ToString(),
        RuntimeInformation.OSDescription,
        mode,
        "http://0.0.0.0:5000");

    if (isHeadless)
    {
        await app.RunAsync();
    }
    else
    {
        await app.StartAsync();
        RunPhotinoWindow();
        await app.StopAsync();
    }
}
finally
{
    Log.CloseAndFlush();
}

static void ConfigureLogging(string logsDirectory)
{
    Directory.CreateDirectory(logsDirectory);

    var existingLogs = Directory.GetFiles(logsDirectory, "session_*.log")
        .Select(f => new FileInfo(f))
        .OrderByDescending(f => f.CreationTimeUtc)
        .ToList();

    if (existingLogs.Count >= 5)
    {
        foreach (var file in existingLogs.Skip(4))
        {
            try { file.Delete(); } catch { }
        }
    }

    var currentSessionLogFile = Path.Combine(
        logsDirectory,
        $"session_{DateTime.UtcNow:yyyy-MM-dd_HH-mm-ss}.log");

    const string outputTemplate = "[{Timestamp:yyyy-MM-dd HH:mm:ss.fff}] [{Level:u3}] [{SourceContext}] {Message:lj}{NewLine}{Exception}";

    Log.Logger = new LoggerConfiguration()
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
        .MinimumLevel.Override("System", LogEventLevel.Warning)
        .MinimumLevel.Override("Microsoft.EntityFrameworkCore", LogEventLevel.Warning)
        .Enrich.FromLogContext()
        .WriteTo.Console(outputTemplate: outputTemplate)
        .WriteTo.File(
            path: currentSessionLogFile,
            outputTemplate: outputTemplate,
            shared: true)
        .CreateLogger();
}

static async Task InitializeDatabaseAsync(WebApplication app)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
    await SettingsEndpoints.LoadStoredSettingsAsync(app.Services);

    var franchiseService = scope.ServiceProvider.GetRequiredService<IFranchiseService>();
    await franchiseService.AutoBackfillFranchisesAsync(db);
}

static void RunPhotinoWindow()
{
    var uiThread = new Thread(() =>
    {
        var window = new Photino.NET.PhotinoWindow()
            .SetTitle("Tsundoku")
            .SetUseOsDefaultSize(false)
            .SetSize(1300, 850)
            .Center()
            .SetDevToolsEnabled(true)
            .Load("http://127.0.0.1:5000");

        window.WaitForClose();
    });

#pragma warning disable CA1416
    uiThread.SetApartmentState(ApartmentState.STA);
#pragma warning restore CA1416
    uiThread.Start();
    uiThread.Join();
}