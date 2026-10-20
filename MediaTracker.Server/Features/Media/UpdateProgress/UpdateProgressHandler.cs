using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
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

        var book = await db.Books.AsNoTracking().Where(x => x.Id == command.Id)
            .Select(x => new { x.CurrentPage, x.TotalPages }).FirstOrDefaultAsync(ct);
        var bookRows = await db.Books
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(
                        x => x.CurrentPage,
                        x => x.TotalPages > 0 && progress > x.TotalPages ? x.TotalPages : progress)
                    .SetProperty(x => x.LastActivityAt, now),
                ct);

        if (bookRows > 0)
        {
            var next = book!.TotalPages > 0 ? Math.Min(progress, book.TotalPages) : progress;
            await RecordProgressAsync(command.Id, $"{book.CurrentPage} стр.", $"{next} стр.", ct);
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        var manga = await db.Manga.AsNoTracking().Where(x => x.Id == command.Id)
            .Select(x => new { x.CurrentChapter, x.TotalChapters }).FirstOrDefaultAsync(ct);
        var mangaRows = await db.Manga
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(
                        x => x.CurrentChapter,
                        x => x.TotalChapters != null && progress > x.TotalChapters ? x.TotalChapters : progress)
                    .SetProperty(x => x.LastActivityAt, now),
                ct);

        if (mangaRows > 0)
        {
            var next = manga!.TotalChapters is > 0 ? Math.Min(progress, manga.TotalChapters.Value) : progress;
            await RecordProgressAsync(command.Id, $"{manga.CurrentChapter} гл.", $"{next} гл.", ct);
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        var game = await db.Games.AsNoTracking().Where(x => x.Id == command.Id)
            .Select(x => x.HoursPlayed).FirstOrDefaultAsync(ct);
        var gameRows = await db.Games
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(x => x.HoursPlayed, progress)
                    .SetProperty(x => x.LastActivityAt, now),
                ct);

        if (gameRows > 0)
        {
            await RecordProgressAsync(command.Id, $"{game ?? 0} ч.", $"{progress} ч.", ct);
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        return Result.Failure(Error.Unsupported("Progress is not supported for this media type."));
    }

    private async Task RecordProgressAsync(Guid mediaId, string? oldValue, string newValue, CancellationToken ct)
    {
        if (oldValue == newValue)
        {
            return;
        }

        db.Events.Add(new MediaEvent
        {
            MediaId = mediaId,
            Type = MediaEventType.ProgressChanged,
            OldValue = oldValue,
            NewValue = newValue,
            CreatedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync(ct);
    }
}
