using Dapper;
using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.UpdateProgress;
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
            "SELECT Id, CurrentPage, TotalPages FROM MediaItems WHERE Id = @id AND MediaType = 'Book'",
            new { id = idStr });
        if (book is not null)
        {
            var next = book.TotalPages > 0 && progress > book.TotalPages ? book.TotalPages : progress;
            await db.Connection.ExecuteAsync(
                "UPDATE MediaItems SET CurrentPage = @next, LastActivityAt = @now WHERE Id = @id",
                new { next, now, id = idStr });
            await RecordProgressAsync(db, command.Id, $"{book.CurrentPage} стр.", $"{next} стр.", ct);
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        // --- Manga ---
        var manga = await db.Connection.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT Id, CurrentChapter, TotalChapters FROM MediaItems WHERE Id = @id AND MediaType = 'Manga'",
            new { id = idStr });
        if (manga is not null)
        {
            var next = manga.TotalChapters is > 0 && progress > manga.TotalChapters ? manga.TotalChapters : progress;
            await db.Connection.ExecuteAsync(
                "UPDATE MediaItems SET CurrentChapter = @next, LastActivityAt = @now WHERE Id = @id",
                new { next, now, id = idStr });
            await RecordProgressAsync(db, command.Id, $"{manga.CurrentChapter} гл.", $"{next} гл.", ct);
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        // --- VideoGame ---
        var game = await db.Connection.QueryFirstOrDefaultAsync<MediaItemRow>(
            "SELECT Id, HoursPlayed FROM MediaItems WHERE Id = @id AND MediaType = 'Game'",
            new { id = idStr });
        if (game is not null)
        {
            await db.Connection.ExecuteAsync(
                "UPDATE MediaItems SET HoursPlayed = @progress, LastActivityAt = @now WHERE Id = @id",
                new { progress, now, id = idStr });
            await RecordProgressAsync(db, command.Id, $"{game.HoursPlayed ?? 0} ч.", $"{progress} ч.", ct);
            AdvancedStatsCalculator.InvalidateCache(cache);
            TasteProfileCalculator.InvalidateCache(cache);
            return Result.Success();
        }

        return Result.Failure(Error.Unsupported("Progress is not supported for this media type."));
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
