using Dapper;
using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.UpdateProgress;

public sealed record UpdateProgressCommand(Guid Id, int CurrentProgress);

public interface IUpdateProgressHandler
{
    Task<Result> HandleAsync(UpdateProgressCommand command, CancellationToken ct);
}

public sealed class UpdateProgressHandler(
    AppDbContext db,
    IValidator<UpdateProgressRequest> validator,
    IMemoryCache cache) : IUpdateProgressHandler
{
    public async Task<Result> HandleAsync(UpdateProgressCommand command, CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(
            new UpdateProgressRequest { CurrentProgress = command.CurrentProgress },
            ct);

        if (validation.ToError() is { } validationError)
        {
            return Result.Failure(validationError);
        }

        var progress = Math.Max(command.CurrentProgress, 0);
        var now = DateTime.UtcNow;

        // --- Book ---
        var idStr = command.Id.ToString().ToUpperInvariant();
        var book = await db.Connection.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT Id, Status, CurrentPage, TotalPages, CurrentChapter, TotalChapters, Book_Format FROM MediaItems WHERE Id = @id AND MediaType = 'Book'",
            new { id = idStr });
        if (book is not null)
        {
            var isNovel = string.Equals(book.Book_Format, "light_novel", StringComparison.OrdinalIgnoreCase)
                || string.Equals(book.Book_Format, "web_novel", StringComparison.OrdinalIgnoreCase);

            if (isNovel)
            {
                var old = book.CurrentChapter ?? 0;
                var next = book.TotalChapters is > 0 && progress > book.TotalChapters.Value ? book.TotalChapters.Value : progress;
                await WriteProgressAsync(
                    db, command.Id, idStr,
                    counterSet: "CurrentChapter = @next",
                    previousStatus: (MediaStatus)book.Status,
                    oldProgress: old,
                    newProgress: next,
                    now, ct);
                await RecordProgressAsync(db, command.Id, $"{book.CurrentChapter ?? 0} гл.", $"{next} гл.", ct);
            }
            else
            {
                var old = book.CurrentPage ?? 0;
                var next = book.TotalPages > 0 && progress > book.TotalPages ? book.TotalPages.Value : progress;
                await WriteProgressAsync(
                    db, command.Id, idStr,
                    counterSet: "CurrentPage = @next",
                    previousStatus: (MediaStatus)book.Status,
                    oldProgress: old,
                    newProgress: next,
                    now, ct);
                await RecordProgressAsync(db, command.Id, $"{book.CurrentPage} стр.", $"{next} стр.", ct);
            }
            // The list projection carries CurrentPage/CurrentChapter/HoursPlayed; a stale cached
            // list would roll the card's optimistic value back on the post-commit refetch.
            MediaListCache.Invalidate();
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        // --- Manga ---
        var manga = await db.Connection.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT Id, Status, CurrentChapter, TotalChapters FROM MediaItems WHERE Id = @id AND MediaType = 'Manga'",
            new { id = idStr });
        if (manga is not null)
        {
            var old = manga.CurrentChapter ?? 0;
            var next = manga.TotalChapters is > 0 && progress > manga.TotalChapters ? manga.TotalChapters.Value : progress;
            await WriteProgressAsync(
                db, command.Id, idStr,
                counterSet: "CurrentChapter = @next",
                previousStatus: (MediaStatus)manga.Status,
                oldProgress: old,
                newProgress: next,
                now, ct);
            await RecordProgressAsync(db, command.Id, $"{manga.CurrentChapter} гл.", $"{next} гл.", ct);
            MediaListCache.Invalidate();
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        // --- VideoGame ---
        var game = await db.Connection.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT Id, Status, HoursPlayed FROM MediaItems WHERE Id = @id AND MediaType = 'Game'",
            new { id = idStr });
        if (game is not null)
        {
            var old = game.HoursPlayed ?? 0;
            await WriteProgressAsync(
                db, command.Id, idStr,
                counterSet: "HoursPlayed = @next",
                previousStatus: (MediaStatus)game.Status,
                oldProgress: old,
                newProgress: progress,
                now, ct,
                next: progress);
            await RecordProgressAsync(db, command.Id, $"{game.HoursPlayed ?? 0} ч.", $"{progress} ч.", ct);
            MediaListCache.Invalidate();
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        return Result.Failure(Error.Unsupported("Progress is not supported for this media type."));
    }

    /// <summary>
    /// Writes the type-specific counter and applies the only automatic status rule (rule 1): a
    /// 0 → 1 step promotes the title to InProgress. Any other progress change leaves the stored
    /// status untouched — dropped stays dropped, on hold stays on hold.
    /// </summary>
    private static async Task WriteProgressAsync(
        AppDbContext db,
        Guid mediaId,
        string idStr,
        string counterSet,
        MediaStatus previousStatus,
        int oldProgress,
        int newProgress,
        DateTime now,
        CancellationToken ct,
        int? next = null)
    {
        var promotes = ProgressStepperRules.PromotesToInProgress(oldProgress, newProgress);
        var sql = promotes
            ? $"UPDATE MediaItems SET {counterSet}, LastActivityAt = @now, Status = @inProgress, StartedAt = COALESCE(StartedAt, @now), FinishedAt = NULL WHERE Id = @id"
            : $"UPDATE MediaItems SET {counterSet}, LastActivityAt = @now WHERE Id = @id";

        await db.Connection.ExecuteAsync(sql, new { next = next ?? newProgress, now, id = idStr, inProgress = (int)MediaStatus.InProgress });

        if (promotes)
        {
            await db.InsertMediaEventAsync(new MediaEvent
            {
                MediaId = mediaId,
                Type = MediaEventType.StatusChanged,
                OldValue = previousStatus.ToString(),
                NewValue = MediaStatus.InProgress.ToString(),
                CreatedAt = now
            }, ct);
        }
    }

    private static async Task RecordProgressAsync(AppDbContext db, Guid mediaId, string? oldValue, string newValue, CancellationToken ct)
    {
        if (oldValue == newValue) return;

        await db.InsertMediaEventAsync(new MediaEvent
        {
            MediaId = mediaId,
            Type = MediaEventType.ProgressChanged,
            OldValue = oldValue,
            NewValue = newValue,
            CreatedAt = DateTime.UtcNow
        }, ct);
    }
}
