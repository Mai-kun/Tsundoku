using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Features.Settings.ApiTokens;
using MediaTracker.Server.Features.Settings.GetCategoryOrder;
using MediaTracker.Server.Features.Settings.GetSourceKeyStatus;
using MediaTracker.Server.Features.Settings.GetSourcePriority;
using MediaTracker.Server.Features.Settings.SaveCategoryOrder;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.Settings.SaveSourcePriority;
using MediaTracker.Server.Features.Settings.ReadingSettings;
using MediaTracker.Server.Features.Settings.ResetData;
using MediaTracker.Server.Features.Settings.TestSource;
using MediaTracker.Server.Features.Settings.ToggleSource;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Features.System.Updates;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.Desktop;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.SocialLib;
using MediaTracker.Server.Infrastructure.Jobs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;

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

        group.MapGet("/app", async ([FromServices] AppDbContext db, CancellationToken ct) =>
            {
                var launchMode = await AppSettingStore.ReadAsync(db, BrowserLauncher.LaunchModeKey, ct)
                    ?? BrowserLauncher.DefaultLaunchMode;
                var closeAction = await AppSettingStore.ReadAsync(db, BrowserLauncher.CloseActionKey, ct)
                    ?? BrowserLauncher.DefaultCloseAction;
                return Results.Ok(new AppSettingsDto(launchMode, closeAction));
            })
            .WithTags("Настройки / Settings")
            .WithSummary("Режим запуска интерфейса и действие при закрытии окна");

        group.MapPut("/app", async (
                AppSettingsDto request,
                [FromServices] AppDbContext db,
                CancellationToken ct) =>
            {
                if (request.LaunchMode is not ("app_window" or "browser_tab"))
                {
                    return Results.BadRequest(new ApiErrorDetail(
                        "launchMode must be 'app_window' or 'browser_tab'."));
                }

                if (request.CloseAction is not ("minimize_to_tray" or "exit_all"))
                {
                    return Results.BadRequest(new ApiErrorDetail(
                        "closeAction must be 'minimize_to_tray' or 'exit_all'."));
                }

                await AppSettingStore.SetAsync(db, BrowserLauncher.LaunchModeKey, request.LaunchMode, ct);
                await AppSettingStore.SetAsync(db, BrowserLauncher.CloseActionKey, request.CloseAction, ct);
                BrowserLauncher.ApplySettings(request.LaunchMode, request.CloseAction);
                return Results.Ok(request);
            })
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить режим запуска интерфейса и действие при закрытии окна");

        group.MapPut("/sources/{id}/key", (
                string id,
                UpdateKeyRequest request,
                [FromServices] ISaveSourceKeyHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new SaveSourceKeyCommand(id, request.ApiKey), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить API-ключ источника");

        group.MapGet("/sources/{id}/key", (
                string id,
                [FromServices] IGetSourceKeyStatusHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new GetSourceKeyStatusQuery(id), ct).ToOk())
            .WithTags("Настройки / Settings")
            .WithSummary("Статус ключа источника (без раскрытия секрета)");

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

        // MangaLib / SocialLib browser-session pickup: the token never leaves this machine — the detector
        // reads the user's own browser localStorage and persists it through the encrypted
        // source-key storage, exactly like the isolated Chromium profile the launcher keeps.
        group.MapPost("/sources/mangalib/detect-token", DetectSocialLibSessionAsync)
            .WithTags("Настройки / Settings")
            .WithSummary("Подхватить авторизацию MangaLib из браузера (Zen / Firefox / Chromium)")
            .WithDescription("Ищет localStorage-сессию SocialLib в профилях браузеров пользователя и сохраняет токен в зашифрованном хранилище.");

        group.MapPost("/sources/sociallib/detect-token", DetectSocialLibSessionAsync)
            .WithTags("Настройки / Settings")
            .WithSummary("Подхватить авторизацию SocialLib из браузера (Zen / Firefox / Chromium)")
            .WithDescription("Ищет localStorage-сессию SocialLib в профилях браузеров пользователя и сохраняет токен в зашифрованном хранилище.");

        group.MapPost("/sources/simkl/detect-token", DetectSimklSessionAsync)
            .WithTags("Настройки / Settings")
            .WithSummary("Подхватить авторизацию Simkl из браузера (Zen / Firefox / Chromium)")
            .WithDescription("Ищет localStorage-сессию Simkl в профилях браузеров пользователя и сохраняет токен в зашифрованном хранилище (отдельно от client_id).");

        group.MapPost("/sources/mangalib/open-login", () =>
            {
                try
                {
                    // Single SocialLib auth center; mangalib.me/ru/login answers 404.
                    Process.Start(new ProcessStartInfo("https://auth.lib.social/auth/login")
                    {
                        UseShellExecute = true,
                    });
                    return Results.NoContent();
                }
                catch (Exception error)
                {
                    return Results.BadRequest(new ApiErrorDetail(
                        $"Не удалось открыть браузер: {error.Message}"));
                }
            })
            .WithTags("Настройки / Settings")
            .WithSummary("Открыть страницу входа MangaLib в системном браузере");

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

        group.MapGet("/export/json", async (
            [FromServices] AppDbContext db,
            CancellationToken ct) =>
        {
            var items = await db.LoadAllMediaItemsAsync(ct);
            var export = items.Select(LibraryExportMapper.ToExportDto).ToList();

            var options = new JsonSerializerOptions(AppJsonSerializerContext.Default.Options)
            {
                WriteIndented = true,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            };
            var typeInfo = (JsonTypeInfo<List<LibraryExportItemDto>>)options.GetTypeInfo(typeof(List<LibraryExportItemDto>));
            var json = JsonSerializer.Serialize(export, typeInfo);

            return Results.Bytes(
                Encoding.UTF8.GetBytes(json),
                contentType: "application/json; charset=utf-8",
                fileDownloadName: $"tsundoku-library-{DateTime.UtcNow:yyyyMMdd}.json");
        })
        .WithTags("Настройки / Settings")
        .WithSummary("Экспорт библиотеки в JSON")
        .WithDescription("Выгружает все тайтлы в человекочитаемом JSON, совместимом с импортом (Custom Import).");

        group.MapGet("/export/csv", async (
            [FromServices] AppDbContext db,
            CancellationToken ct) =>
        {
            var items = await db.LoadAllMediaItemsAsync(ct);
            var csv = LibraryExportMapper.ToCsv(items.Select(LibraryExportMapper.ToExportDto).ToList());

            return Results.Bytes(
                Encoding.UTF8.GetBytes(csv),
                contentType: "text/csv; charset=utf-8",
                fileDownloadName: $"tsundoku-library-{DateTime.UtcNow:yyyyMMdd}.csv");
        })
        .WithTags("Настройки / Settings")
        .WithSummary("Экспорт библиотеки в CSV")
        .WithDescription("Выгружает все тайтлы в RFC 4180 CSV с UTF-8 BOM (корректно открывается в Excel), совместим с импортом (Custom Import).");

        group.MapGet("/update/check", async (
            [FromServices] IUpdateService updateService,
            CancellationToken ct) => Results.Ok(await updateService.CheckForUpdatesAsync(ct)))
            .WithTags("Настройки / Settings")
            .WithSummary("Проверка обновлений");

        group.MapGet("/storage", ([FromServices] AppPaths appPaths) =>
        {
            var appDir = AppPaths.GetAppDirectory();
            var config = appPaths.GetOrRecreateStorageConfig();
            return Results.Ok(new StorageInfoResponse(
                config.Mode ?? "default",
                appPaths.DataDirectory,
                Path.Combine(appDir, "data"),
                AppPaths.GetSystemDataRoot(),
                config.CustomPath,
                appPaths.IsFirstRunSetupRequired));
        }).WithTags("Настройки / Settings").WithSummary("Получить настройки хранилища");

        group.MapPost("/storage", async (
            [FromBody] StorageRequest request,
            [FromServices] AppPaths currentPaths,
            [FromServices] AppDbContext dbContext,
            [FromServices] IHostApplicationLifetime hostLifetime) =>
            {
                var appDir = AppPaths.GetAppDirectory();
                var configPath = AppPaths.GetWritableStorageConfigPath(request.Mode);
                // Captured BEFORE the config write: after it the first-run flag is already false.
                var wasFirstRun = currentPaths.IsFirstRunSetupRequired;

                string targetDataDir = request.Mode switch
                {
                    "portable" => Path.Combine(appDir, "data"),
                    "custom" => request.CustomPath ?? throw new ArgumentException("CustomPath required for custom mode"),
                    _ => AppPaths.GetSystemDataRoot()
                };

                targetDataDir = Path.GetFullPath(targetDataDir);

                if (request.MigrateExistingData && !string.Equals(targetDataDir, currentPaths.DataDirectory, StringComparison.OrdinalIgnoreCase))
                {
                    Directory.CreateDirectory(targetDataDir);

                    // 1. Database
                    if (File.Exists(currentPaths.DatabaseFilePath))
                    {
                        var targetDbPath = Path.Combine(targetDataDir, Path.GetFileName(currentPaths.DatabaseFilePath));
                        if (File.Exists(targetDbPath))
                        {
                            File.Delete(targetDbPath);
                        }

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
                currentPaths.SaveStorageConfig(configPath, config);

                // Leaving the first run: the provisional database folder (created before the user
                // chose a mode) holds nothing but the freshly seeded schema — the setup modal
                // blocks any real use — and when migration was requested its copy already lives
                // at the target. Remove the whole provisional folder so no stray Tsundoku dir
                // lingers in the system location after the user picked a different home.
                if (wasFirstRun
                    && !string.Equals(targetDataDir, currentPaths.DataDirectory, StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        Directory.Delete(currentPaths.DataDirectory, recursive: true);
                        Serilog.Log.Information(
                            "[Storage] Removed the provisional first-run data folder {Path}",
                            currentPaths.DataDirectory);
                    }
                    catch (Exception error)
                    {
                        Serilog.Log.Warning(error, "Failed to remove the provisional first-run data folder");
                    }
                }

                if (string.Equals(request.Mode, "portable", StringComparison.OrdinalIgnoreCase))
                {
                    // Mode switch to portable: the previously created default-mode folder inside
                    // LocalApplicationData must not linger. Only an accidentally created empty
                    // folder (no files, only empty subfolders) is removed — user data is preserved.
                    var legacyDir = AppPaths.GetSystemDataRoot();
                    try
                    {
                        if (Directory.Exists(legacyDir)
                            && !Directory.EnumerateFileSystemEntries(legacyDir).Any()
                            && !string.Equals(configPath, Path.Combine(legacyDir, "storage.json"), StringComparison.OrdinalIgnoreCase))
                        {
                            foreach (var subDir in Directory.EnumerateDirectories(legacyDir))
                            {
                                if (!Directory.EnumerateFileSystemEntries(subDir).Any())
                                {
                                    Directory.Delete(subDir);
                                }
                            }
                            if (!Directory.EnumerateFileSystemEntries(legacyDir).Any())
                            {
                                Directory.Delete(legacyDir);
                            }
                        }
                    }
                    catch (Exception error)
                    {
                        Serilog.Log.Warning(error, "Failed to clean up the legacy Tsundoku folder");
                    }
                }

                var needsRestart = !string.Equals(targetDataDir, currentPaths.DataDirectory, StringComparison.OrdinalIgnoreCase);

                if (needsRestart)
                {
                    _ = Task.Run(async () =>
                    {
                        await Task.Delay(300);
                        // Окно Chromium не закрывается (Program.cs пропускает CloseBrowser при
                        // запланированном перезапуске): оно показывает спиннер и само перезагрузится,
                        // когда новый бэкенд начнёт отвечать. Новый процесс стартует свернутым и
                        // усыновляет живое окно по PID.
                        AppRestartService.ScheduleRestartKeepingWindow();
                        hostLifetime.StopApplication();
                    });
                }

                // Тело сообщает, будет ли перезапуск: фронтенд в этом случае ждёт «лёг → поднялся»
                // и только потом перезагружает страницу (иначе гонка с умирающим старым сервером).
                return Results.Accepted(value: new StorageRestartResponse(needsRestart));
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

        group.MapGet("/offline-databases", async (
            [FromServices] OfflineDatabaseManager dbManager,
            CancellationToken ct) => Results.Ok(await dbManager.GetSummaryAsync(ct)))
            .WithTags("Настройки / Settings")
            .WithSummary("Получить статус офлайн-баз данных");

        group.MapPost("/offline-databases/reindex", (
            [FromServices] OfflineDatabaseManager dbManager,
            [FromServices] IJobManager jobManager) =>
        {
            dbManager.EnqueuePendingImports(jobManager, force: true);
            return Results.Accepted();
        })
            .WithTags("Настройки / Settings")
            .WithSummary("Переиндексировать офлайн-дампы");

        group.MapPost("/franchises/reindex", async (
            [FromServices] AppDbContext db,
            [FromServices] IFranchiseService franchiseService,
            CancellationToken ct) =>
        {
            var updatedCount = await franchiseService.AutoBackfillFranchisesAsync(db, ct);
            MediaListCache.Invalidate();
            return Results.Ok(new FranchiseReindexResponse(updatedCount));
        })
            .WithTags("Настройки / Settings")
            .WithSummary("Пересканировать франшизы");

        group.MapDelete("/offline-databases/dumps/{fileName}", (
            string fileName,
            [FromServices] OfflineDatabaseManager dbManager) =>
        {
            // Only dumps discoverable in the offline directories are accepted; anything else is a
            // rejection rather than a guess, so the endpoint never deletes an arbitrary file.
            if (!dbManager.DeleteSourceDump(fileName))
            {
                return Results.NotFound(new { error = $"Source dump not found for '{fileName}'" });
            }

            return Results.NoContent();
        })
            .WithTags("Настройки / Settings")
            .WithSummary("Удалить исходный дамп офлайн-базы (освободить место)");

        group.MapGet("/offline-mode", async (
            [FromServices] AppDbContext db,
            [FromServices] OfflineDatabaseManager dbManager,
            CancellationToken ct) =>
        {
            var val = await AppSettingStore.ReadAsync(db, AppSettingStore.OfflineModeKey, ct);
            var offlineMode = string.Equals(val, "true", StringComparison.OrdinalIgnoreCase);
            var hasDatabases = dbManager.HasAnyDatabase;
            return Results.Ok(new OfflineModeResponse(offlineMode, hasDatabases));
        })
            .WithTags("Настройки / Settings")
            .WithSummary("Получить статус офлайн-режима");

        group.MapPut("/offline-mode", async (
            UpdateOfflineModeRequest request,
            [FromServices] AppDbContext db,
            [FromServices] ISourcePriorityService priorityService,
            [FromServices] IMemoryCache cache,
            CancellationToken ct) =>
        {
            await AppSettingStore.SetAsync(db, AppSettingStore.OfflineModeKey, request.OfflineMode ? "true" : "false", ct);
            cache.Set("settings:offline_mode", request.OfflineMode, TimeSpan.FromMinutes(10));
            priorityService.InvalidateCache();
            return Results.Ok(new UpdateOfflineModeRequest(request.OfflineMode));
        })
            .WithTags("Настройки / Settings")
            .WithSummary("Сохранить статус офлайн-режима");

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

    private static async Task<IResult> DetectSocialLibSessionAsync(
        [FromServices] ISaveSourceKeyHandler saveKey,
        CancellationToken ct)
    {
        var session = await BrowserSessionDetector.TryDetectSessionAsync(ct);
        if (session is null)
        {
            return Results.NotFound(new MangalibSessionResponse(
                Success: false,
                UserId: null,
                Username: null,
                Source: null,
                Message: "Сессия SocialLib в браузерах не найдена. Войдите на lib.social в браузере и повторите попытку."));
        }

        await saveKey.HandleAsync(
            new SaveSourceKeyCommand("sociallib", session.Token), ct);
        var saved = await saveKey.HandleAsync(
            new SaveSourceKeyCommand(ImportOnlyKeySources.MangaLib, session.Token), ct);
        if (!saved.TryGetValue(out var savedValue))
        {
            return Results.BadRequest(new ApiErrorDetail(
                saved.Error?.Message ?? "Не удалось сохранить токен."));
        }

        return Results.Ok(new MangalibSessionResponse(
            Success: savedValue.Success,
            UserId: session.UserId,
            Username: session.Username,
            Source: session.SourcePath,
            Message: null));
    }

    /// <summary>
    /// Simkl's browser-session pickup. The token is bound to <see cref="ImportOnlyKeySources.SimklSession"/>,
    /// not to the provider's own key slot: that slot holds the public client_id, which Simkl Auth V2
    /// requires on every request even when the Bearer is present.
    /// </summary>
    private static async Task<IResult> DetectSimklSessionAsync(
        [FromServices] ISaveSourceKeyHandler saveKey,
        CancellationToken ct)
    {
        var session = await BrowserSessionDetector.TryDetectSimklSessionAsync(ct);
        if (session is null)
        {
            return Results.NotFound(new MangalibSessionResponse(
                Success: false,
                UserId: null,
                Username: null,
                Source: null,
                Message: "Сессия Simkl в браузерах не найдена. Войдите на simkl.com в браузере и повторите попытку."));
        }

        var saved = await saveKey.HandleAsync(
            new SaveSourceKeyCommand(ImportOnlyKeySources.SimklSession, session.Token), ct);
        if (!saved.TryGetValue(out var savedValue))
        {
            return Results.BadRequest(new ApiErrorDetail(
                saved.Error?.Message ?? "Не удалось сохранить токен."));
        }

        return Results.Ok(new MangalibSessionResponse(
            Success: savedValue.Success,
            UserId: session.UserId,
            Username: session.Username,
            Source: session.SourcePath,
            Message: null));
    }
}

public sealed record OfflineModeResponse(bool OfflineMode, bool HasDatabases);
public sealed record UpdateOfflineModeRequest(bool OfflineMode);
public sealed record StorageRequest(string Mode, string? CustomPath, bool MigrateExistingData);
public sealed record AppSettingsDto(string LaunchMode, string CloseAction);
public sealed record ToggleSourceRequest(bool Enabled);
public sealed record UpdateKeyRequest(string? ApiKey);

/// <summary>AOT-safe response for the franchise rescan: anonymous types have no source-gen JSON
/// metadata, so the first click on "Пересканировать франшизы" died in the serializer under
/// NativeAOT before this record replaced it.</summary>
public sealed record FranchiseReindexResponse(int UpdatedCount);

/// <summary>
/// One flat library row in the privacy-first export. The column names are exactly the aliases
/// CustomImportParser matches case-insensitively, so a downloaded file re-imports without edits.
/// </summary>
public sealed record LibraryExportItemDto(
    string Title,
    string? OriginalTitle,
    string? RomajiTitle,
    string Type,
    string Status,
    int? Score,
    int? Progress,
    int? TotalCount,
    string? Author,
    string? Studio,
    int? ReleaseYear,
    string? ReleaseDate,
    string? Genres,
    string? Notes,
    string? ExternalSource,
    string? ExternalId);

/// <summary>Projects typed media entities onto the flat import-compatible export rows.</summary>
public static class LibraryExportMapper
{
    public static LibraryExportItemDto ToExportDto(MediaItem item) => new(
        Title: item.Title,
        OriginalTitle: item.OriginalTitle,
        RomajiTitle: item switch
        {
            Manga manga => manga.RomajiTitle,
            TvShow show => show.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            _ => null,
        },
        Type: ToTypeName(item),
        Status: ToStatusName(item.Status),
        Score: item.Score,
        Progress: item switch
        {
            Manga manga => manga.CurrentChapter,
            Book book => book.CurrentPage,
            TvShow show => show.TotalEpisodesWatched,
            VideoGame game => game.HoursPlayed,
            _ => null,
        },
        TotalCount: item switch
        {
            Manga manga => manga.TotalChapters,
            Book book => book.TotalPages > 0 ? book.TotalPages : null,
            TvShow show => show.TotalEpisodesCount > 0 ? show.TotalEpisodesCount : null,
            _ => null,
        },
        Author: item switch
        {
            Manga manga => manga.Author,
            Book book => string.IsNullOrWhiteSpace(book.Author) ? null : book.Author,
            _ => null,
        },
        Studio: item switch
        {
            TvShow show => show.Studio,
            Movie movie => movie.Studio,
            VideoGame game => game.Studio,
            _ => null,
        },
        ReleaseYear: item.ReleaseYear,
        ReleaseDate: item.ReleaseDate?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        Genres: item.Genres,
        Notes: item.Notes,
        ExternalSource: item.ExternalSource,
        ExternalId: item.ExternalId);

    private static string ToTypeName(MediaItem item) => item switch
    {
        VideoGame => "game",
        Book => "book",
        Manga => "manga",
        Movie => "movie",
        // "anime" is not a stored media type: it round-trips through the import parser back to
        // a TvShow carrying the IsAnime flag, so it must not collapse into "tvshow".
        TvShow { IsAnime: true } => "anime",
        TvShow => "tvshow",
        _ => throw new InvalidOperationException($"Unsupported media item '{item.GetType().Name}'."),
    };

    private static string ToStatusName(MediaStatus status) => status switch
    {
        MediaStatus.InProgress => "in_progress",
        MediaStatus.Completed => "completed",
        MediaStatus.OnHold => "on_hold",
        MediaStatus.Dropped => "dropped",
        _ => "planned",
    };

    /// <summary>Serialises rows as RFC 4180 CSV: CRLF line breaks, quote-doubling, UTF-8 BOM.</summary>
    public static string ToCsv(List<LibraryExportItemDto> items)
    {
        var sb = new StringBuilder();
        sb.Append('\uFEFF');
        sb.Append(
            "title,originalTitle,romajiTitle,type,status,score,progress,totalCount,author,studio," +
            "releaseYear,releaseDate,genres,notes,externalSource,externalId\r\n");
        foreach (var item in items)
        {
            sb.Append(EscapeCsvField(item.Title)).Append(',')
                .Append(EscapeCsvField(item.OriginalTitle)).Append(',')
                .Append(EscapeCsvField(item.RomajiTitle)).Append(',')
                .Append(EscapeCsvField(item.Type)).Append(',')
                .Append(EscapeCsvField(item.Status)).Append(',')
                .Append(EscapeCsvField(item.Score)).Append(',')
                .Append(EscapeCsvField(item.Progress)).Append(',')
                .Append(EscapeCsvField(item.TotalCount)).Append(',')
                .Append(EscapeCsvField(item.Author)).Append(',')
                .Append(EscapeCsvField(item.Studio)).Append(',')
                .Append(EscapeCsvField(item.ReleaseYear)).Append(',')
                .Append(EscapeCsvField(item.ReleaseDate)).Append(',')
                .Append(EscapeCsvField(item.Genres)).Append(',')
                .Append(EscapeCsvField(item.Notes)).Append(',')
                .Append(EscapeCsvField(item.ExternalSource)).Append(',')
                .Append(EscapeCsvField(item.ExternalId))
                .Append("\r\n");
        }

        return sb.ToString();
    }

    private static string EscapeCsvField(object? value)
    {
        var text = value?.ToString() ?? "";
        var mustQuote = text.Contains(',') || text.Contains('"') || text.Contains('\r') || text.Contains('\n');
        if (!mustQuote)
        {
            return text;
        }

        return $"\"{text.Replace("\"", "\"\"")}\"";
    }
}
