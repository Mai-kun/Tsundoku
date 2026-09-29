using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.Endpoints;
using MediaTracker.Server.Infrastructure;
using MediaTracker.Server.Middleware;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Security;
using MediaTracker.Server.Services.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using OpenApiUi;
using Serilog;
using Serilog.Events;

var logsDirectory = Path.Combine(Directory.GetCurrentDirectory(), "data", "logs");
Directory.CreateDirectory(logsDirectory);

var existingLogs = Directory.GetFiles(logsDirectory, "session_*.log")
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
        }
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

try
{
    var builder = WebApplication.CreateBuilder(args);
    builder.Host.UseSerilog();

    var isContainer = Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true";
    var isHeadless = isContainer
                     || args.Contains("--headless")
                     || Environment.GetEnvironmentVariable("HEADLESS") == "true";

    var appPaths = new AppPaths(isContainer
        ? builder.Environment.ContentRootPath
        : Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Tsundoku"));

    ApplyConfigurationSources(builder, appPaths);

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

    builder.Services.Configure<ExternalApiOptions>(builder.Configuration.GetSection("ExternalApis"));

    builder.Services.AddSingleton<IEncryptionService, EncryptionService>();

    const string DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Tsundoku/1.0";
    var defaultTimeout = TimeSpan.FromSeconds(4);

    builder.Services.AddHttpClient("AniList", client =>
    {
        client.BaseAddress = new Uri("https://graphql.anilist.co/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("Kitsu", client =>
    {
        client.BaseAddress = new Uri("https://kitsu.io/api/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("OpenLibrary", client =>
    {
        client.BaseAddress = new Uri("https://openlibrary.org/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("Tmdb", client =>
    {
        client.BaseAddress = new Uri("https://api.themoviedb.org/3/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("Rawg", client =>
    {
        client.BaseAddress = new Uri("https://api.rawg.io/api/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("Jikan", client =>
    {
        client.BaseAddress = new Uri("https://api.jikan.moe/v4/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("MangaUpdates", client =>
    {
        client.BaseAddress = new Uri("https://api.mangaupdates.com/v1/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });
    builder.Services.AddHttpClient("MangaDex", client =>
    {
        client.BaseAddress = new Uri("https://api.mangadex.org/");
        client.Timeout = defaultTimeout;
        client.DefaultRequestHeaders.UserAgent.ParseAdd(DefaultUserAgent);
    });

    builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anime");
    builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anime:anilist");
    builder.Services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("anime:jikan");
    builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anilist");
    builder.Services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("jikan");

    builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("manga");
    builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("manga:anilist");
    builder.Services.AddKeyedTransient<IMetadataProvider, MangaDexMetadataProvider>("manga:mangadex");
    builder.Services.AddKeyedTransient<IMetadataProvider, MangaUpdatesMetadataProvider>("manga:mangaupdates");
    builder.Services.AddKeyedTransient<IMetadataProvider, JikanMetadataProvider>("manga:jikan");
    builder.Services.AddKeyedTransient<IMetadataProvider, MangaDexMetadataProvider>("mangadex");
    builder.Services.AddKeyedTransient<IMetadataProvider, MangaUpdatesMetadataProvider>("mangaupdates");

    builder.Services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("book");
    builder.Services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("book:openlibrary");
    builder.Services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("openlibrary");

    builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("movie");
    builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("movie:tmdb");

    builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tvshow");
    builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tvshow:tmdb");
    builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tmdb");

    builder.Services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("game");
    builder.Services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("game:rawg");
    builder.Services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("rawg");

    builder.Services.AddTransient<MetadataAggregatorService>();

    builder.Services.AddHttpClient<IImageStorageService, ImageStorageService>(client =>
        client.Timeout = TimeSpan.FromSeconds(5));

    var app = builder.Build();

    app.UseSerilogRequestLogging();

    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Database.Migrate();
        SettingsEndpoints.LoadStoredSettingsAsync(app.Services).GetAwaiter().GetResult();
        MediaEndpoints.AutoBackfillFranchisesAsync(db).GetAwaiter().GetResult();
    }

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
        OnPrepareResponse = context =>
        {
            context.Context.Response.Headers.CacheControl = "public, max-age=31536000, immutable";
        }
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

        await app.StopAsync();
    }
}
finally
{
    Log.CloseAndFlush();
}

static void ApplyConfigurationSources(WebApplicationBuilder builder, AppPaths appPaths)
{
    var configuration = (IConfigurationBuilder)builder.Configuration;

    var frameworkSources = configuration.Sources.ToList();

    configuration.Sources.Clear();

    configuration.AddInMemoryCollection(ReadEmbeddedDefaults());

    configuration.AddJsonFile(
        new PhysicalFileProvider(appPaths.DataDirectory),
        Path.GetFileName(appPaths.SettingsFilePath),
        optional: true,
        reloadOnChange: false);

    foreach (var source in frameworkSources)
    {
        configuration.Add(source);
    }
}

static IReadOnlyDictionary<string, string?> ReadEmbeddedDefaults()
{
    var assembly = typeof(Program).Assembly;
    var resourceName = assembly.GetManifestResourceNames()
                           .FirstOrDefault(name =>
                               name.EndsWith("appsettings.json", StringComparison.OrdinalIgnoreCase))
                       ?? throw new InvalidOperationException(
                           "Embedded default settings (appsettings.json) were not found in the assembly.");

    using var stream = assembly.GetManifestResourceStream(resourceName)
        ?? throw new InvalidOperationException($"Embedded resource '{resourceName}' could not be opened.");

    using var document = JsonDocument.Parse(stream);
    if (document.RootElement.ValueKind != JsonValueKind.Object)
    {
        return new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
    }

    var values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
    FlattenJsonConfiguration(document.RootElement, prefix: null, values);
    return values;
}

static void FlattenJsonConfiguration(
    JsonElement element,
    string? prefix,
    IDictionary<string, string?> values)
{
    switch (element.ValueKind)
    {
        case JsonValueKind.Object:
            foreach (var property in element.EnumerateObject())
            {
                var key = prefix is null ? property.Name : $"{prefix}:{property.Name}";
                FlattenJsonConfiguration(property.Value, key, values);
            }

            break;

        case JsonValueKind.Array:
            var index = 0;
            foreach (var item in element.EnumerateArray())
            {
                FlattenJsonConfiguration(item, $"{prefix}:{index}", values);
                index++;
            }

            break;

        case JsonValueKind.Null:
            values[prefix!] = null;
            break;

        case JsonValueKind.String:
            values[prefix!] = element.GetString();
            break;

        default:
            values[prefix!] = element.GetRawText();
            break;
    }
}