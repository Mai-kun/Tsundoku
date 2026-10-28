using System.Diagnostics;
using System.Text.Json;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Features.Settings.ApiTokens;
using MediaTracker.Server.Features.Settings.GetCategoryOrder;
using MediaTracker.Server.Features.Settings.GetSourcePriority;
using MediaTracker.Server.Features.Settings.SaveCategoryOrder;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.Settings.SaveSourcePriority;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Features.Settings.ResetData;
using MediaTracker.Server.Features.Settings.TestSource;
using MediaTracker.Server.Features.Settings.ToggleSource;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Features.System.Updates;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class SettingsEndpoints
{
    public static IEndpointRouteBuilder MapSettingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/settings");

        group.MapPost("/reset", (
                ResetDataRequest request,
                [FromServices] IResetDataHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(request, ct).ToNoContent())
            .WithTags("Настройки / Settings")
            .WithSummary("Сброс данных медиатеки")
            .WithDescription("Удаляет данные медиатеки с возможностью сохранения настроек источников.");

        group.MapGet("/sources", ([FromServices] IGetSourcesHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Список внешних источников метаданных");

        group.MapPut("/sources/{id}/key", (
                string id,
                UpdateKeyRequest request,
                [FromServices] ISaveSourceKeyHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveSourceKeyCommand(id, request.ApiKey), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить API-ключ источника");

        group.MapPut("/sources/{id}/toggle", (
                string id,
                ToggleSourceRequest request,
                [FromServices] IToggleSourceHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new ToggleSourceCommand(id, request.Enabled), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Включить или отключить источник");

        group.MapPost("/sources/{id}/test", (
                string id,
                [FromServices] ITestSourceHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new TestSourceQuery(id), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Проверить доступность источника и валидность ключа");

        group.MapGet("/category-order", ([FromServices] IGetCategoryOrderHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Получить порядок отображения категорий");

        group.MapPut("/category-order", (
                string[] order,
                [FromServices] ISaveCategoryOrderHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveCategoryOrderCommand(order), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить порядок отображения категорий");

        group.MapGet("/source-priority", ([FromServices] IGetSourcePriorityHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Получить приоритеты источников для типов медиа");

        group.MapPut("/source-priority", (
                Dictionary<string, string[]> priority,
                [FromServices] ISaveSourcePriorityHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveSourcePriorityCommand(priority), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить приоритеты источников для типов медиа");

        group.MapGet("/reading", ([FromServices] IGetReadingSettingsHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Получить настройки читалки и трекинга");

        group.MapPut("/reading", (
                ReadingSettingsDto request,
                [FromServices] ISaveReadingSettingsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(request, ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить настройки читалки и трекинга");

        group.MapGet("/tokens", ([FromServices] IGetApiTokensHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Список активных API-токенов");

        group.MapPost("/tokens", (
                CreateApiTokenRequest request,
                [FromServices] ICreateApiTokenHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(request, ct).ToCreated("/api/settings/tokens"))
            .WithTags("Настройки / Settings")
            .WithSummary("Создать персональный API-токен");

        group.MapDelete("/tokens/{id:guid}", (
                Guid id,
                [FromServices] IRevokeApiTokenHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(id, ct).ToNoContent())
            .WithTags("Настройки / Settings")
            .WithSummary("Отозвать API-токен");

        group.MapGet("/backup/export", async (
            [FromServices] MediaTracker.Server.Infrastructure.Storage.IBackupService backupService,
            CancellationToken ct) =>
        {
            var result = await backupService.CreateBackupArchiveAsync(ct);
            if (result.IsFailure || result.Value is null)
            {
                return result.Problem();
            }

            var fileName = $"tsundoku-backup-{DateTime.UtcNow:yyyyMMdd-HHmmss}.zip";
            return Results.File(
                result.Value,
                contentType: "application/zip",
                fileDownloadName: fileName);
        })
        .WithTags("Настройки / Settings")
        .WithSummary("Экспорт резервной копии (ZIP-архив)")
        .WithDescription("Создает и выгружает полный ZIP-архив с базой данных SQLite и обложками тайтлов.");

        group.MapPost("/backup/restore", async (
            IFormFile backupFile,
            [FromServices] MediaTracker.Server.Infrastructure.Storage.IBackupService backupService,
            CancellationToken ct) =>
        {
            if (backupFile is null || backupFile.Length == 0)
            {
                return Results.BadRequest(HttpResultMapper.CreateProblem(
                    MediaTracker.Server.Domain.Common.Error.Validation("Файл бэкапа не предоставлен.")));
            }

            await using var stream = backupFile.OpenReadStream();
            var result = await backupService.RestoreBackupArchiveAsync(stream, ct);
            return result.ToHttpResult();
        }).DisableAntiforgery()
        .WithTags("Настройки / Settings")
        .WithSummary("Восстановление из резервной копии")
        .WithDescription("Принимает ZIP-архив бэкапа и восстанавливает базу данных и медиафайлы.");

        group.MapGet("/update/check", async (
            [FromServices] IUpdateService updateService,
            CancellationToken ct) => Results.Ok(await updateService.CheckForUpdatesAsync(ct)))
            .WithTags("Настройки / Settings")
            .WithSummary("Проверка обновлений");

        group.MapGet("/storage", ([FromServices] AppPaths appPaths) =>
        {
            var appDir = AppContext.BaseDirectory;
            var configPath = Path.Combine(appDir, "storage.json");
            var mode = "default";
            if (File.Exists(configPath))
            {
                var config = JsonSerializer.Deserialize(File.ReadAllText(configPath), AppJsonSerializerContext.Default.StorageConfig);
                mode = config?.Mode ?? "default";
            }
            return Results.Ok(new StorageInfoResponse(
                mode,
                appPaths.DataDirectory,
                Path.Combine(appDir, "data"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku"),
                appPaths.IsFirstRunSetupRequired));
        }).WithTags("Настройки / Settings").WithSummary("Получить настройки хранилища");

        group.MapPost("/storage", async (
            [FromBody] StorageRequest request,
            [FromServices] AppPaths currentPaths,
            [FromServices] AppDbContext dbContext,
            [FromServices] IHostApplicationLifetime hostLifetime) =>
            {
                var appDir = AppContext.BaseDirectory;
                var configPath = Path.Combine(appDir, "storage.json");

                string targetDataDir = request.Mode switch
                {
                    "portable" => Path.Combine(appDir, "data"),
                    "custom" => request.CustomPath ?? throw new ArgumentException("CustomPath required for custom mode"),
                    _ => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tsundoku")
                };

                if (request.MigrateExistingData && targetDataDir != currentPaths.DataDirectory)
                {
                    Directory.CreateDirectory(targetDataDir);

                    // 1. Database
                    if (File.Exists(currentPaths.DatabaseFilePath))
                    {
                        var targetDbPath = Path.Combine(targetDataDir, Path.GetFileName(currentPaths.DatabaseFilePath));
                        var escapedTargetDbPath = targetDbPath.Replace("'", "''");
                        var conn2 = dbContext.Connection;
                        if (conn2.State != global::System.Data.ConnectionState.Open) await conn2.OpenAsync();
                        using var vacuumCmd = conn2.CreateCommand();
                        vacuumCmd.CommandText = $"VACUUM INTO '{escapedTargetDbPath}';";
                        await vacuumCmd.ExecuteNonQueryAsync();
                    }

                    // 2. Media and Covers
                    foreach (var dir in new[] { currentPaths.MediaDirectory, currentPaths.CoversDirectory })
                    {
                        if (Directory.Exists(dir))
                        {
                            var targetSubDir = Path.Combine(targetDataDir, Path.GetFileName(dir));
                            Directory.CreateDirectory(targetSubDir);
                            CopyDirectory(dir, targetSubDir);
                        }
                    }

                    // 3. Secret Key
                    var oldSecretKey = Path.Combine(currentPaths.DataDirectory, ".secret.key");
                    if (File.Exists(oldSecretKey))
                    {
                        File.Copy(oldSecretKey, Path.Combine(targetDataDir, ".secret.key"), overwrite: true);
                    }
                }

                var config = new StorageConfig { Mode = request.Mode, CustomPath = request.CustomPath };
                File.WriteAllText(configPath, JsonSerializer.Serialize(config, AppJsonSerializerContext.Default.StorageConfig));

                Task.Run(() =>
                {
                    Thread.Sleep(1000);
                    var startInfo = new ProcessStartInfo(Environment.ProcessPath!, string.Join(" ", Environment.GetCommandLineArgs().Skip(1)))
                    {
                        UseShellExecute = true
                    };
                    Process.Start(startInfo);
                    hostLifetime.StopApplication();
                });
                return Results.Accepted();
            }).WithTags("Настройки / Settings").WithSummary("Сохранить настройки хранилища");

        group.MapPost("/update/apply", async (
            [FromServices] IUpdateService updateService,
            CancellationToken ct) =>
            {
                await updateService.ApplyUpdateAsync(ct);
                return Results.Accepted();
            })
            .WithTags("Настройки / Settings")
            .WithSummary("Применить обновление");

        return app;
    }

    private static void CopyDirectory(string sourceDir, string targetDir)
    {
        Directory.CreateDirectory(targetDir);
        foreach (var file in Directory.GetFiles(sourceDir))
            File.Copy(file, Path.Combine(targetDir, Path.GetFileName(file)), overwrite: true);
        foreach (var directory in Directory.GetDirectories(sourceDir))
            CopyDirectory(directory, Path.Combine(targetDir, Path.GetFileName(directory)));
    }
}

public sealed record StorageRequest(string Mode, string? CustomPath, bool MigrateExistingData);
public sealed record ToggleSourceRequest(bool Enabled);
public sealed record UpdateKeyRequest(string? ApiKey);
