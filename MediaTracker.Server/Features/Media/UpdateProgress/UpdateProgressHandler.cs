using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
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

        var bookRows = await db.Books
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(
                s => s.SetProperty(
                    x => x.CurrentPage,
                    x => x.TotalPages > 0 && progress > x.TotalPages ? x.TotalPages : progress),
                ct);

        if (bookRows > 0)
        {
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        var mangaRows = await db.Manga
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(
                s => s.SetProperty(
                    x => x.CurrentChapter,
                    x => x.TotalChapters != null && progress > x.TotalChapters ? x.TotalChapters : progress),
                ct);

        if (mangaRows > 0)
        {
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        var gameRows = await db.Games
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.HoursPlayed, progress), ct);

        if (gameRows > 0)
        {
            cache.Remove(AdvancedStatsCalculator.CacheKey);
            return Result.Success();
        }

        return Result.Failure(Error.Unsupported("Progress is not supported for this media type."));
    }
}
