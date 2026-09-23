using System.Text.Json.Serialization;
using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.Endpoints;
using MediaTracker.Server.Middleware;
using MediaTracker.Server.Services.External;
using Microsoft.EntityFrameworkCore;
using OpenApiUi;

var builder = WebApplication.CreateBuilder(args);

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

app.MapMediaEndpoints();
app.MapSeasonEndpoints();
app.MapExternalMediaEndpoints();

app.MapFallbackToFile("index.html");

app.Run();