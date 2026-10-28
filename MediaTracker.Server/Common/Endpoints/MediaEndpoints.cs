using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.External.EnrichMetadata;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.External.RelinkMedia;
using MediaTracker.Server.Features.History.ClearHistory;
using MediaTracker.Server.Features.History.DeleteHistoryEvent;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.DeleteMedia;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetCreatorSummary;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.GetRecommendations;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.PendingMatches;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using Microsoft.AspNetCore.Mvc;

namespace MediaTracker.Server.Common.Endpoints;

public static class MediaEndpoints
{
    public static IEndpointRouteBuilder MapMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media");

        group.MapPost("/import/file", async (
            [FromForm] IFormFile file, [FromForm] string provider, [FromForm] bool? skipDuplicates,
            [FromForm] Guid? targetListId, [FromForm] string? newListName,
            [FromForm] bool? createCustomLists, [FromForm] string? customFolderStatus,
            [FromForm] string? customFolderConfigs,
            [FromServices] ImportMediaHandler handler, CancellationToken ct) =>
        {
            try
            {
                MediaStatus? parsedStatus = null;
                if (!string.IsNullOrWhiteSpace(customFolderStatus) &&
                    Enum.TryParse<MediaStatus>(customFolderStatus, true, out var parsed))
                {
                    parsedStatus = parsed;
                }

                return Results.Ok(await handler.ImportFileAsync(new ImportFileRequest(
                    file,
                    provider,
                    skipDuplicates ?? true,
                    targetListId,
                    newListName,
                    createCustomLists ?? false,
                    parsedStatus,
                    customFolderConfigs), ct));
            }
            catch (FormatException error) { return Results.BadRequest(new ApiErrorDetail(error.Message)); }
            catch (HttpRequestException error) { return Results.BadRequest(new ApiErrorDetail($"Steam request failed: {error.Message}")); }
        }).DisableAntiforgery()
        .WithTags("Импорт / Import")
        .WithSummary("Пакетный импорт из файла")
        .WithDescription("Поддерживает форматы MAL/Shikimori (XML/JSON), Letterboxd (CSV), Goodreads (CSV), Steam (JSON), MangaLib (JSON/CSV) и Custom (JSON/CSV).");

        group.MapPost("/import/steam", async (
            SteamImportRequest request, [FromServices] ImportMediaHandler handler, CancellationToken ct) =>
        {
            try { return Results.Ok(await handler.ImportSteamAsync(request, ct)); }
            catch (FormatException error) { return Results.BadRequest(new ApiErrorDetail(error.Message)); }
            catch (HttpRequestException error) { return Results.BadRequest(new ApiErrorDetail($"Steam request failed: {error.Message}")); }
        })
        .WithTags("Импорт / Import")
        .WithSummary("Импорт игр по профилю SteamID");

        group.MapPost("/import/anilist-profile", async (
            AniListProfileRequest request, [FromServices] ImportMediaHandler handler, CancellationToken ct) =>
        {
            try
            {
                var result = await handler.ImportAniListProfileAsync(request, ct);
                return result.TryGetValue(out var imported)
                    ? Results.Ok(imported)
                    : Results.BadRequest(new ApiErrorDetail(result.Error?.Message ?? "Import failed."));
            }
            catch (FormatException error) { return Results.BadRequest(new ApiErrorDetail(error.Message)); }
            catch (HttpRequestException error) { return Results.BadRequest(new ApiErrorDetail($"AniList request failed: {error.Message}")); }
        })
        .WithTags("Импорт / Import")
        .WithSummary("Импорт аниме и манги по никнейму AniList");

        group.MapPost("/import/mangalib-profile", async (
            MangaLibProfileRequest request, [FromServices] ImportMediaHandler handler, CancellationToken ct) =>
        {
            try
            {
                var result = await handler.ImportMangaLibProfileAsync(request, ct);
                return result.TryGetValue(out var imported)
                    ? Results.Ok(imported)
                    : Results.BadRequest(new ApiErrorDetail(result.Error?.Message ?? "Import failed."));
            }
            catch (FormatException error) { return Results.BadRequest(new ApiErrorDetail(error.Message)); }
            catch (HttpRequestException error) { return Results.BadRequest(new ApiErrorDetail($"SocialLib request failed: {error.Message}")); }
        })
        .WithTags("Импорт / Import")
        .WithSummary("Импорт закладок по профилю SocialLib (MangaLib / AnimeLib / RanobeLib и др.)");


        group.MapGet("/", (
                [FromServices] IGetMediaListHandler handler,
                string? type,
                MediaStatus? status,
                bool? isAnime,
                string? search,
                string? sortBy,
                string? sortOrder,
                CancellationToken ct) =>
            handler.HandleAsync(new GetMediaListQuery(type, status, isAnime, search, sortBy, sortOrder), ct)
                .ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Список тайтлов медиатеки")
            .WithDescription("Возвращает плоский список медиа с поддержкой фильтрации по типу, статусу, аниме-признаку, текстовому поиску и сортировке.");

        group.MapGet("/stats", ([FromServices] IGetMediaStatsHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToOk())
            .WithTags("Аналитика / Stats")
            .WithSummary("Базовая статистика медиатеки");

        group.MapGet("/stats/advanced", (
                [FromQuery] string? scope,
                [FromServices] IGetMediaStatsHandler handler,
                CancellationToken ct) =>
            handler.HandleAdvancedAsync(scope, ct).ToOk())
            .WithTags("Аналитика / Stats")
            .WithSummary("Продвинутая аналитика, стрик и тепловая карта");

        group.MapGet("/stats/taste-profile", (
                [FromQuery] string? scope,
                [FromServices] IGetMediaStatsHandler handler,
                CancellationToken ct) =>
            handler.HandleTasteProfileAsync(scope, ct).ToOk())
            .WithTags("Аналитика / Stats")
            .WithSummary("Психологический профиль вкуса")
            .WithDescription("Возвращает культурный архетип, SVG-радар жанров, синдром потерянного времени, критический диссонанс и анатомию дропа.");

        group.MapGet("/creator-summary", (
                string name,
                string role,
                Guid? excludeId,
                [FromServices] IGetCreatorSummaryHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(name, role, excludeId, ct))
            .WithTags("Медиатека / Media")
            .WithSummary("Сводка по автору или создателю")
            .WithDescription("Возвращает список работ автора или создателя в медиатеке.");

        group.MapGet("/{id:guid}", (
                Guid id,
                [FromServices] IGetMediaDetailHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new GetMediaDetailQuery(id), ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Детальная карточка тайтла")
            .WithDescription("Возвращает полную карточку со всеми метаданными, синопсисом, сезонами, томами, ачивками и связями.");

        group.MapPost("/", async (
            CreateMediaRequest request,
            [FromServices] ICreateMediaHandler handler,
            CancellationToken ct) =>
        {
            var result = await handler.HandleAsync(new CreateMediaCommand(request), ct);

            if (!result.TryGetValue(out var created))
            {
                return HttpResultMapper.Problem(result.Error!);
            }

            return Results.Created($"/api/media/{created.Id}", created);
        })
        .WithTags("Медиатека / Media")
        .WithSummary("Создать тайтл вручную");

        group.MapPut("/{id:guid}", (
                Guid id,
                UpdateMediaRequest request,
                [FromServices] IUpdateMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateMediaCommand(id, request), ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Обновить метаданные тайтла")
            .WithDescription("Обновляет поля тайтла (название, оценка, личные заметки, цитаты, платформа, детальный рейтинг).");

        group.MapPut("/{id:guid}/status", (
                Guid id,
                UpdateStatusRequest request,
                [FromServices] IUpdateStatusHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateStatusCommand(id, request.Status, request.DropReason, request.DropNotes), ct).ToNoContent())
            .WithTags("Медиатека / Media")
            .WithSummary("Сменить статус тайтла")
            .WithDescription("Меняет статус (0: Planned, 1: InProgress, 2: Completed, 3: OnHold, 4: Dropped). Поддерживает опциональные причину и заметку дропа.");

        group.MapPut("/{id:guid}/progress", (
                Guid id,
                UpdateProgressRequest request,
                [FromServices] IUpdateProgressHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new UpdateProgressCommand(id, request.CurrentProgress), ct).ToNoContent())
            .WithTags("Медиатека / Media")
            .WithSummary("Обновить прогресс (страницы, главы, часы)")
            .WithDescription("Принимает абсолютное число: текущую страницу книги, главу манги или наигранные часы игры. Фиксирует событие в истории.");

        // Safe-merge: the client sends fillMissing when the user picked "keep my edits" in the
        // refresh dialog, which turns the overwrite into a gap fill.
        group.MapPost("/{id:guid}/refresh", (
                Guid id,
                [FromBody] RefreshMetadataRequest? request,
                [FromServices] IRefreshMetadataHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new RefreshMetadataCommand(id, request?.FillMissing ?? false),
                ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Обновить все метаданные из внешнего источника")
            .WithDescription("Запускает фоновую задачу обновления постера, дат, синопсиса, каста сэйю, трейлера и связей франшизы.");

        // Enrich metadata: same gap-fill rules, but the source is the one the user picked in the dialog
        // rather than whatever the row was originally matched on.
        group.MapPost("/{id:guid}/enrich", (
                Guid id,
                [FromBody] EnrichMetadataRequest? request,
                [FromServices] IEnrichMetadataHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new EnrichMetadataCommand(id, request?.Source),
                ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Дополнить пустые поля тайтла")
            .WithDescription("Фоново заполняет только пустые поля из выбранного провайдера без перезаписи существующих данных.");

        // Re-link: point an existing row at another provider's entity (Kinopoisk -> TMDb).
        group.MapPost("/{id:guid}/relink", (
                Guid id,
                RelinkMediaRequest request,
                [FromServices] IRelinkMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new RelinkMediaCommand(id, request), ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Сменить внешний источник (Re-link)")
            .WithDescription("Принудительно перепривязывает тайтл к другому провайдеру по указанному ExternalId.");

        // Ambiguous import matches: the enrichment job parked rows here (NeedsReview) for the user to
        // confirm, skip or resolve by hand. There is no {id:guid} to collide with, since that route
        // is guid-constrained and these literals are not.
        group.MapGet("/pending-matches", async (
                [FromServices] IGetPendingMatchesHandler handler,
                CancellationToken ct) =>
            Results.Ok(await handler.HandleAsync(ct)))
            .WithTags("Медиатека / Media")
            .WithSummary("Тайтлы, ожидающие подтверждения совпадения")
            .WithDescription("Все строки библиотеки в статусе NeedsReview: что импортировано и какие кандидаты нашлись.");

        group.MapPost("/{id:guid}/resolve-match", (
                Guid id,
                ResolveMatchRequest request,
                [FromServices] IResolveMatchHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new ResolveMatchCommand(id, request), ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Подтвердить совпадение из списка кандидатов")
            .WithDescription("Скачивает полные данные выбранного кандидата, применяет метаданные (прогресс и оценка не трогаются) и возвращает обновлённый тайтл.");

        group.MapPost("/resolve-all-by-priority", async (
                [FromServices] IResolveAllByPriorityHandler handler,
                CancellationToken ct) =>
            Results.Ok(await handler.HandleAsync(ct)))
            .WithTags("Медиатека / Media")
            .WithSummary("Выбрать первого кандидата во всех спорных тайтлах")
            .WithDescription("Для каждого NeedsReview тайтла берёт лучшего кандидата, ставит Syncing и запускает фоновое обогащение; возвращает число выбранных строк.");

        group.MapPost("/{id:guid}/dismiss-match", async (
                Guid id,
                [FromServices] IDismissMatchHandler handler,
                CancellationToken ct) =>
            await handler.HandleAsync(new DismissMatchCommand(id), ct)
                ? Results.NoContent()
                : Results.NotFound(new ApiErrorDetail($"Media item '{id}' was not found.")))
            .WithTags("Медиатека / Media")
            .WithSummary("Оставить тайтл без привязки")
            .WithDescription("Убирает спорных кандидатов и возвращает тайтл в статус Ready без изменения данных.");

        group.MapPost("/dismiss-all-matches", async (
                [FromServices] IDismissAllMatchesHandler handler,
                CancellationToken ct) =>
            Results.Ok(new DismissedCount(await handler.HandleAsync(ct))))
            .WithTags("Медиатека / Media")
            .WithSummary("Отклонить все спорные совпадения разом")
            .WithDescription("Переводит все NeedsReview тайтлы в Ready и очищает их списки кандидатов.");

        // Recommendations live on the row, so this one endpoint both fetches and replays: a call inside the
        // 30-day window is answered from SQLite without the provider being contacted at all.
        group.MapPost("/{id:guid}/recommendations", (
                Guid id,
                string? source,
                bool? forceRefresh,
                [FromServices] IGetRecommendationsHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(
                new GetRecommendationsCommand(id, source, forceRefresh ?? false),
                ct).ToOk())
            .WithTags("Медиатека / Media")
            .WithSummary("Получить персональные рекомендации для тайтла");

        group.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IDeleteMediaHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new DeleteMediaCommand(id), ct).ToNoContent())
            .WithTags("Медиатека / Media")
            .WithSummary("Удалить тайтл и его ассеты");

        var historyGroup = app.MapGroup("/api/history");

        historyGroup.MapGet("/", (Guid? mediaId, DateOnly? date, [FromServices] IGetHistoryEventsHandler handler, CancellationToken ct) =>
            handler.HandleAsync(new GetHistoryEventsQuery(mediaId, date), ct).ToOk())
            .WithTags("История / History")
            .WithSummary("Журнал активности (с фильтрацией)")
            .WithDescription("Возвращает хронологический список действий. Поддерживает query-параметры mediaId (для конкретного тайтла) и date (для конкретного дня).");

        historyGroup.MapDelete("/", ([FromServices] IClearHistoryHandler handler, CancellationToken ct) =>
            handler.HandleAsync(ct).ToNoContent())
            .WithTags("История / History")
            .WithSummary("Очистить весь журнал истории");

        historyGroup.MapDelete("/{id:guid}", (
                Guid id,
                [FromServices] IDeleteHistoryEventHandler handler,
                CancellationToken ct) =>
            handler.HandleAsync(new DeleteHistoryEventCommand(id), ct).ToNoContent())
            .WithTags("История / History")
            .WithSummary("Удалить одну запись из журнала");

        return app;
    }
}

public sealed record RefreshMetadataRequest(bool FillMissing = false);

public sealed record EnrichMetadataRequest(string? Source = null);
