using MediaTracker.Server.Common.Http;
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

        return app;
    }
}

public sealed record ToggleSourceRequest(bool Enabled);

public sealed record UpdateKeyRequest(string? ApiKey);
