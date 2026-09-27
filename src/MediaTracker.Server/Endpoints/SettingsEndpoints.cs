using System.Text.Json;
using MediaTracker.Server.Data;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Security;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Endpoints;

public static class SettingsEndpoints
{
    public static IEndpointRouteBuilder MapSettingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/settings");

        group.MapGet("/sources", GetSources);
        group.MapPut("/sources/{id}/key", SaveSourceKey);
        group.MapGet("/category-order", GetCategoryOrder);
        group.MapPut("/category-order", SaveCategoryOrder);
        group.MapGet("/source-priority", GetSourcePriority);
        group.MapPut("/source-priority", SaveSourcePriority);

        return app;
    }

    public static async Task LoadStoredSettingsAsync(IServiceProvider services, CancellationToken ct = default)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var encryption = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        var options = scope.ServiceProvider.GetRequiredService<IOptions<ExternalApiOptions>>().Value;

        var tmdbSetting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ApiKey_tmdb", ct);
        if (tmdbSetting is not null && !string.IsNullOrWhiteSpace(tmdbSetting.Value))
        {
            var decrypted = encryption.Decrypt(tmdbSetting.Value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.TmdbApiKey = decrypted;
            }
        }

        var rawgSetting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ApiKey_rawg", ct);
        if (rawgSetting is not null && !string.IsNullOrWhiteSpace(rawgSetting.Value))
        {
            var decrypted = encryption.Decrypt(rawgSetting.Value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.RawgApiKey = decrypted;
            }
        }
    }

    private static IResult GetSources(
        IOptions<ExternalApiOptions> options,
        AppDbContext db)
    {
        var tmdbKey = options.Value.TmdbApiKey;
        var rawgKey = options.Value.RawgApiKey;

        var sources = new[]
        {
            new SourceInfo(
                Id: "anilist",
                Name: "AniList",
                Description: "Anime and Manga metadata & ratings provider",
                MediaTypes: ["anime", "manga"],
                RequiresApiKey: false,
                IsConfigured: true,
                HasKey: true,
                MaskedKey: null
            ),
            new SourceInfo(
                Id: "kitsu",
                Name: "Kitsu",
                Description: "Anime ratings provider (community scores)",
                MediaTypes: ["anime"],
                RequiresApiKey: false,
                IsConfigured: true,
                HasKey: true,
                MaskedKey: null
            ),
            new SourceInfo(
                Id: "tmdb",
                Name: "The Movie Database (TMDb)",
                Description: "Movies and TV Shows metadata & ratings provider",
                MediaTypes: ["movie", "tvshow"],
                RequiresApiKey: true,
                IsConfigured: !string.IsNullOrWhiteSpace(tmdbKey),
                HasKey: !string.IsNullOrWhiteSpace(tmdbKey),
                MaskedKey: MaskKey(tmdbKey)
            ),
            new SourceInfo(
                Id: "rawg",
                Name: "RAWG Video Games Database",
                Description: "Video games metadata & ratings provider",
                MediaTypes: ["game"],
                RequiresApiKey: true,
                IsConfigured: !string.IsNullOrWhiteSpace(rawgKey),
                HasKey: !string.IsNullOrWhiteSpace(rawgKey),
                MaskedKey: MaskKey(rawgKey)
            ),
            new SourceInfo(
                Id: "openlibrary",
                Name: "OpenLibrary",
                Description: "Books metadata & ratings provider",
                MediaTypes: ["book"],
                RequiresApiKey: false,
                IsConfigured: true,
                HasKey: true,
                MaskedKey: null
            ),
            new SourceInfo(
                Id: "jikan",
                Name: "MyAnimeList (Jikan)",
                Description: "Anime and Manga metadata & ratings provider",
                MediaTypes: ["anime", "manga"],
                RequiresApiKey: false,
                IsConfigured: true,
                HasKey: true,
                MaskedKey: null
            ),
            new SourceInfo(
                Id: "mangaupdates",
                Name: "MangaUpdates",
                Description: "Manga and Manhwa metadata & ratings provider",
                MediaTypes: ["manga"],
                RequiresApiKey: false,
                IsConfigured: true,
                HasKey: true,
                MaskedKey: null
            )
        };

        return Results.Ok(sources);
    }

    private static async Task<IResult> SaveSourceKey(
        string id,
        UpdateKeyRequest request,
        AppDbContext db,
        IEncryptionService encryption,
        IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var normalizedId = id.Trim().ToLowerInvariant();
        if (normalizedId is not ("tmdb" or "rawg"))
        {
            return Results.BadRequest(new { message = $"Source '{id}' does not require an API key." });
        }

        var key = request.ApiKey?.Trim() ?? string.Empty;
        var encrypted = string.IsNullOrEmpty(key) ? string.Empty : encryption.Encrypt(key);
        var settingKey = $"ApiKey_{normalizedId}";

        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == settingKey, ct);
        if (setting is null)
        {
            setting = new AppSetting
            {
                Key = settingKey,
                Value = encrypted,
                UpdatedAt = DateTime.UtcNow
            };
            db.Settings.Add(setting);
        }
        else
        {
            setting.Value = encrypted;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);

        // Update in-memory options immediately
        if (normalizedId == "tmdb")
        {
            options.Value.TmdbApiKey = key;
        }
        else if (normalizedId == "rawg")
        {
            options.Value.RawgApiKey = key;
        }

        return Results.Ok(new { success = true, hasKey = !string.IsNullOrEmpty(key), maskedKey = MaskKey(key) });
    }

    private static async Task<IResult> GetCategoryOrder(AppDbContext db, CancellationToken ct)
    {
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "SearchCategoryOrder", ct);
        if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<string[]>(setting.Value);
                if (parsed is { Length: > 0 })
                {
                    return Results.Ok(parsed);
                }
            }
            catch
            {
            }
        }

        string[] defaultOrder = ["anime", "movie", "tvshow", "manga", "game", "book"];
        return Results.Ok(defaultOrder);
    }

    private static async Task<IResult> SaveCategoryOrder(
        string[] order,
        AppDbContext db,
        CancellationToken ct)
    {
        if (order == null || order.Length == 0)
        {
            return Results.BadRequest();
        }

        var json = JsonSerializer.Serialize(order);
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "SearchCategoryOrder", ct);
        if (setting is null)
        {
            setting = new AppSetting
            {
                Key = "SearchCategoryOrder",
                Value = json,
                UpdatedAt = DateTime.UtcNow
            };
            db.Settings.Add(setting);
        }
        else
        {
            setting.Value = json;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        return Results.Ok(order);
    }

    private static async Task<IResult> GetSourcePriority(AppDbContext db, CancellationToken ct)
    {
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "SourcePriority", ct);
        if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize<Dictionary<string, string[]>>(setting.Value);
                if (parsed != null && parsed.Count > 0)
                {
                    return Results.Ok(parsed);
                }
            }
            catch
            {
            }
        }

        return Results.Ok(MetadataAggregatorService.DefaultSourcePriority);
    }

    private static async Task<IResult> SaveSourcePriority(
        Dictionary<string, string[]> priority,
        AppDbContext db,
        CancellationToken ct)
    {
        if (priority == null || priority.Count == 0)
        {
            return Results.BadRequest();
        }

        var json = JsonSerializer.Serialize(priority);
        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "SourcePriority", ct);
        if (setting is null)
        {
            setting = new AppSetting
            {
                Key = "SourcePriority",
                Value = json,
                UpdatedAt = DateTime.UtcNow
            };
            db.Settings.Add(setting);
        }
        else
        {
            setting.Value = json;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        return Results.Ok(priority);
    }

    private static string? MaskKey(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        if (key.Length <= 8)
        {
            return new string('•', key.Length);
        }

        return $"{key[..4]}••••••••{key[^4..]}";
    }

    public sealed record UpdateKeyRequest(string? ApiKey);

    public sealed record SourceInfo(
        string Id,
        string Name,
        string Description,
        string[] MediaTypes,
        bool RequiresApiKey,
        bool IsConfigured,
        bool HasKey,
        string? MaskedKey);
}
