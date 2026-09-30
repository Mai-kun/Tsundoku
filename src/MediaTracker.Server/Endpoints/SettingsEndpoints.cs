using System.Text.Json;
using MediaTracker.Server.Data;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Security;
using MediaTracker.Server.Services.Settings;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Endpoints;

public static class SettingsEndpoints
{
    private const string CategoryOrderSettingKey = "SearchCategoryOrder";
    private const string SourcePrioritySettingKey = "SourcePriority";

    private static readonly string[] DefaultCategoryOrder = ["anime", "movie", "tvshow", "manga", "game", "book"];

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

        await AppSettingStore.SetAsync(db, $"ApiKey_{normalizedId}", encrypted, ct);

        options.Value.SetKey(normalizedId, key);

        return Results.Ok(new { success = true, hasKey = !string.IsNullOrEmpty(key), maskedKey = MaskKey(key) });
    }

    private static async Task<IResult> GetCategoryOrder(AppDbContext db, CancellationToken ct)
    {
        var stored = await AppSettingStore.ReadAsync(db, CategoryOrderSettingKey, ct);
        var parsed = TryDeserialize<string[]>(stored);
        return Results.Ok(parsed is { Length: > 0 } ? parsed : DefaultCategoryOrder);
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

        await AppSettingStore.SetAsync(db, CategoryOrderSettingKey, JsonSerializer.Serialize(order), ct);
        return Results.Ok(order);
    }

    private static async Task<IResult> GetSourcePriority(AppDbContext db, CancellationToken ct)
    {
        var stored = await AppSettingStore.ReadAsync(db, SourcePrioritySettingKey, ct);
        var merged = SourcePriorityService.MergeWithDefaults(TryDeserialize<Dictionary<string, string[]>>(stored));

        // Newly shipped sources get folded into the saved order on first read, so persist the result.
        var json = JsonSerializer.Serialize(merged);
        if (stored is not null && stored != json)
        {
            await AppSettingStore.SetAsync(db, SourcePrioritySettingKey, json, ct);
        }

        return Results.Ok(merged);
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

        await AppSettingStore.SetAsync(db, SourcePrioritySettingKey, JsonSerializer.Serialize(priority), ct);
        priorityService.InvalidateCache();
        return Results.Ok(priority);
    }

    /// <summary>Returns null for absent, blank or corrupt values so a bad row falls back to defaults.</summary>
    private static T? TryDeserialize<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return default;
        }

        try
        {
            return JsonSerializer.Deserialize<T>(json);
        }
        catch (JsonException)
        {
            return default;
        }
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
}
