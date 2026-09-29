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
        group.MapPut("/sources/{id}/toggle", ToggleSource);
        group.MapPost("/sources/{id}/test", TestSource);
        group.MapGet("/category-order", GetCategoryOrder);
        group.MapPut("/category-order", SaveCategoryOrder);
        group.MapGet("/source-priority", GetSourcePriority);
        group.MapPut("/source-priority", SaveSourcePriority);
        group.MapGet("/recommendation-services", GetRecommendationServices);
        group.MapPut("/recommendation-services/{id}/key", SaveRecommendationServiceKey);
        group.MapPost("/recommendation-services/{id}/test", TestRecommendationService);

        return app;
    }

    public static async Task LoadStoredSettingsAsync(IServiceProvider services, CancellationToken ct = default)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var encryption = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        var options = scope.ServiceProvider.GetRequiredService<IOptions<ExternalApiOptions>>().Value;
        var providers = scope.ServiceProvider.GetRequiredService<IEnumerable<IMetadataProvider>>();

        foreach (var provider in providers.Where(p => p.RequiresApiKey).DistinctBy(p => p.Id))
        {
            var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == $"ApiKey_{provider.Id}", ct);
            if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
            {
                var decrypted = encryption.Decrypt(setting.Value);
                if (!string.IsNullOrWhiteSpace(decrypted))
                {
                    options.SetKey(provider.Id, decrypted);
                }
            }
        }

        var tdSetting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ApiKey_tastedive", ct);
        if (tdSetting is not null && !string.IsNullOrWhiteSpace(tdSetting.Value))
        {
            var decrypted = encryption.Decrypt(tdSetting.Value);
            if (!string.IsNullOrWhiteSpace(decrypted))
            {
                options.SetKey("tastedive", decrypted);
            }
        }
    }

    private static async Task<IResult> GetSources(
        IEnumerable<IMetadataProvider> providers,
        IOptions<ExternalApiOptions> options,
        ISourcePriorityService priorityService,
        CancellationToken ct)
    {
        var disabled = await priorityService.GetDisabledSourcesAsync(ct);
        var sources = providers
            .DistinctBy(p => p.Id)
            .Select(p =>
            {
                var key = options.Value.GetKey(p.Id);
                var hasKey = !p.RequiresApiKey || !string.IsNullOrWhiteSpace(key);

                return new SourceInfo(
                    Id: p.Id,
                    Name: p.Name,
                    Description: p.Description,
                    MediaTypes: [.. p.MediaTypes],
                    RequiresApiKey: p.RequiresApiKey,
                    IsConfigured: hasKey,
                    HasKey: hasKey,
                    MaskedKey: MaskKey(key),
                    IsEnabled: !disabled.Contains(p.Id.ToLowerInvariant()) && !disabled.Contains(MediaMerger.NormalizeSourceKey(p.Id))
                );
            })
            .OrderByDescending(s => s.IsEnabled)
            .ToList();

        return Results.Ok(sources);
    }

    private static async Task<IResult> SaveSourceKey(
        string id,
        UpdateKeyRequest request,
        AppDbContext db,
        IEncryptionService encryption,
        IOptions<ExternalApiOptions> options,
        IEnumerable<IMetadataProvider> providers,
        CancellationToken ct)
    {
        var normalizedId = id.Trim().ToLowerInvariant();
        var provider = providers.FirstOrDefault(p => p.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase));
        if (provider?.RequiresApiKey is false)
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
        options.Value.SetKey(normalizedId, key);

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
            catch { }
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
        Dictionary<string, string[]>? parsed = null;
        if (setting is not null && !string.IsNullOrWhiteSpace(setting.Value))
        {
            try
            {
                parsed = JsonSerializer.Deserialize<Dictionary<string, string[]>>(setting.Value);
            }
            catch { }
        }

        var merged = MergeWithDefaultPriorities(parsed);

        // If newly added sources were merged into the saved settings, persist to DB
        var newJson = JsonSerializer.Serialize(merged);
        if (setting is not null && setting.Value != newJson)
        {
            setting.Value = newJson;
            setting.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        return Results.Ok(merged);
    }

    private static Dictionary<string, string[]> MergeWithDefaultPriorities(Dictionary<string, string[]>? userPriority)
    {
        var result = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);

        foreach (var (type, defaultSources) in SourcePriorityService.DefaultPriorities)
        {
            if (userPriority != null && userPriority.TryGetValue(type, out var userSources) && userSources?.Length > 0)
            {
                var list = new List<string>();
                foreach (var s in userSources)
                {
                    if (defaultSources.Contains(s, StringComparer.OrdinalIgnoreCase) && !list.Contains(s, StringComparer.OrdinalIgnoreCase))
                    {
                        list.Add(s);
                    }
                }
                foreach (var s in defaultSources)
                {
                    if (!list.Contains(s, StringComparer.OrdinalIgnoreCase))
                    {
                        list.Add(s);
                    }
                }
                result[type] = [.. list];
            }
            else
            {
                result[type] = defaultSources;
            }
        }

        return result;
    }

    private static async Task<IResult> SaveSourcePriority(
        Dictionary<string, string[]> priority,
        AppDbContext db,
        ISourcePriorityService priorityService,
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
        priorityService.InvalidateCache();
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

    private static async Task<IResult> ToggleSource(
        string id,
        ToggleSourceRequest request,
        ISourcePriorityService priorityService,
        CancellationToken ct)
    {
        await priorityService.SetSourceEnabledAsync(id, request.Enabled, ct);
        return Results.Ok(new { success = true, isEnabled = request.Enabled });
    }

    private static async Task<IResult> TestSource(
        string id,
        IEnumerable<IMetadataProvider> providers,
        CancellationToken ct)
    {
        var normalizedId = id.Trim().ToLowerInvariant();
        var provider = providers.FirstOrDefault(p =>
            p.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase)
            || MediaMerger.NormalizeSourceKey(p.Id) == MediaMerger.NormalizeSourceKey(normalizedId));

        if (provider is null)
        {
            return Results.NotFound(new { message = $"Source '{id}' not found." });
        }

        var result = await provider.TestConnectionAsync(ct);
        return Results.Ok(result);
    }

    private static IResult GetRecommendationServices(IOptions<ExternalApiOptions> options)
    {
        var key = options.Value.TasteDiveApiKey;
        var list = new[]
        {
            new RecommendationServiceInfo(
                Id: "tastedive",
                Name: "TasteDive",
                Description: "Сервис рекомендаций похожих игр на основе вкусов и предпочтений",
                RequiresApiKey: true,
                IsConfigured: !string.IsNullOrWhiteSpace(key),
                HasKey: !string.IsNullOrWhiteSpace(key),
                MaskedKey: MaskKey(key)
            )
        };
        return Results.Ok(list);
    }

    private static async Task<IResult> SaveRecommendationServiceKey(
        string id,
        UpdateKeyRequest request,
        AppDbContext db,
        IEncryptionService encryption,
        IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var normalizedId = id.Trim().ToLowerInvariant();
        if (normalizedId != "tastedive")
        {
            return Results.NotFound(new { message = $"Recommendation service '{id}' not found." });
        }

        var key = request.ApiKey?.Trim() ?? string.Empty;
        var encrypted = string.IsNullOrEmpty(key) ? string.Empty : encryption.Encrypt(key);

        var setting = await db.Settings.FirstOrDefaultAsync(s => s.Key == "ApiKey_tastedive", ct);
        if (setting is null)
        {
            db.Settings.Add(new AppSetting
            {
                Key = "ApiKey_tastedive",
                Value = encrypted,
                UpdatedAt = DateTime.UtcNow
            });
        }
        else
        {
            setting.Value = encrypted;
            setting.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        options.Value.SetKey("tastedive", key);

        var masked = MaskKey(key);
        return Results.Ok(new { success = true, hasKey = !string.IsNullOrWhiteSpace(key), maskedKey = masked });
    }

    private static async Task<IResult> TestRecommendationService(
        string id,
        IHttpClientFactory httpClientFactory,
        IOptions<ExternalApiOptions> options,
        CancellationToken ct)
    {
        var normalizedId = id.Trim().ToLowerInvariant();
        if (normalizedId != "tastedive")
        {
            return Results.NotFound(new { message = $"Recommendation service '{id}' not found." });
        }

        var key = options.Value.TasteDiveApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return Results.Ok(new ConnectionTestResult(false, 0, "API key is required"));
        }

        var client = httpClientFactory.CreateClient();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));
            var res = await client.GetAsync($"https://tastedive.com/api/similar?q=portal&type=game&k={Uri.EscapeDataString(key)}", cts.Token);
            sw.Stop();
            if (res.IsSuccessStatusCode)
            {
                return Results.Ok(new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK"));
            }
            return Results.Ok(new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"HTTP {(int)res.StatusCode}: {res.ReasonPhrase}"));
        }
        catch (Exception ex)
        {
            sw.Stop();
            return Results.Ok(new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message));
        }
    }

    public sealed record ToggleSourceRequest(bool Enabled);

    public sealed record UpdateKeyRequest(string? ApiKey);

    public sealed record SourceInfo(
        string Id,
        string Name,
        string Description,
        string[] MediaTypes,
        bool RequiresApiKey,
        bool IsConfigured,
        bool HasKey,
        string? MaskedKey,
        bool IsEnabled);

    public sealed record RecommendationServiceInfo(
        string Id,
        string Name,
        string Description,
        bool RequiresApiKey,
        bool IsConfigured,
        bool HasKey,
        string? MaskedKey);
}
