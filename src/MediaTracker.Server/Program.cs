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

builder.WebHost.UseUrls("http://0.0.0.0:5000");

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection")
        ?? "Data Source=tracker.db"));

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

app.UseDefaultFiles();
app.UseStaticFiles();

var coversPath = Path.Combine(app.Environment.ContentRootPath, "data", "covers");
Directory.CreateDirectory(coversPath);

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(coversPath),
    RequestPath = "/covers"
});

app.MapMediaEndpoints();
app.MapSeasonEndpoints();
app.MapExternalMediaEndpoints();

app.MapFallbackToFile("index.html");

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

uiThread.SetApartmentState(ApartmentState.STA);
uiThread.Start();
uiThread.Join();

await app.StopAsync();