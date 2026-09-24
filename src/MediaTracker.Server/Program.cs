using System.Text.Json;
using System.Text.Json.Serialization;
using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.Endpoints;
using MediaTracker.Server.Middleware;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using OpenApiUi;

var builder = WebApplication.CreateBuilder(args);

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
    options.UseSqlite(connectionString));

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

builder.Services.AddHttpClient("AniList", client => client.BaseAddress = new Uri("https://graphql.anilist.co/"));
builder.Services.AddHttpClient("OpenLibrary", client => client.BaseAddress = new Uri("https://openlibrary.org/"));
builder.Services.AddHttpClient("Tmdb", client => client.BaseAddress = new Uri("https://api.themoviedb.org/3/"));
builder.Services.AddHttpClient("Rawg", client => client.BaseAddress = new Uri("https://api.rawg.io/api/"));

builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("anime");
builder.Services.AddKeyedTransient<IMetadataProvider, AniListMetadataProvider>("manga");
builder.Services.AddKeyedTransient<IMetadataProvider, OpenLibraryMetadataProvider>("book");
builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("movie");
builder.Services.AddKeyedTransient<IMetadataProvider, TmdbMetadataProvider>("tvshow");
builder.Services.AddKeyedTransient<IMetadataProvider, RawgMetadataProvider>("game");

builder.Services.AddTransient<MetadataAggregatorService>();

builder.Services.AddHttpClient<IImageStorageService, ImageStorageService>(client =>
    client.Timeout = TimeSpan.FromSeconds(5));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
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
    RequestPath = "/covers"
});

app.MapMediaEndpoints();
app.MapSeasonEndpoints();
app.MapExternalMediaEndpoints();

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