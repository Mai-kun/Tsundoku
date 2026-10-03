using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.UpdateProgress;

public sealed record UpdateProgressCommand(Guid Id, int CurrentProgress);

public interface IUpdateProgressHandler
{
    Task<Result> HandleAsync(UpdateProgressCommand command, CancellationToken ct);
}

/// <summary>
/// The progress stepper for books, manga and games. The clamping total and the row type live in the
/// same table, so the whole write is one UPDATE per candidate type: no SELECT, no entity
/// materialization, no change tracker entry.
/// </summary>
public sealed class UpdateProgressHandler(
    AppDbContext db,
    IValidator<UpdateProgressRequest> validator) : IUpdateProgressHandler
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
            return Result.Success();
        }

        var gameRows = await db.Games
            .Where(x => x.Id == command.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.HoursPlayed, progress), ct);

        return gameRows > 0
            ? Result.Success()
            : Result.Failure(Error.Unsupported("Progress is not supported for this media type."));
    }
}
