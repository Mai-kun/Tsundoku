using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Volumes.UpdateVolumeProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Volumes.UpdateVolumeProgress;

public sealed record UpdateVolumeProgressCommand(Guid VolumeId, int? CurrentPage, int? CurrentChapter);

public interface IUpdateVolumeProgressHandler
{
    Task<Result> HandleAsync(UpdateVolumeProgressCommand command, CancellationToken ct);
}

/// <summary>
/// The volume stepper. The volume is projected down to the counters the verdict needs and written as
/// one UPDATE with no tracked entity; the parent manga is advanced to match.
/// </summary>
public sealed class UpdateVolumeProgressHandler(
    AppDbContext db,
    IValidator<UpdateVolumeProgressRequest> validator) : IUpdateVolumeProgressHandler
{
    public async Task<Result> HandleAsync(UpdateVolumeProgressCommand command, CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(
            new UpdateVolumeProgressRequest
            {
                CurrentPage = command.CurrentPage,
                CurrentChapter = command.CurrentChapter,
            },
            ct);

        if (validation.ToError() is { } validationError)
        {
            return Result.Failure(validationError);
        }

        var volume = await db.MangaVolumes
            .AsNoTracking()
            .Where(item => item.Id == command.VolumeId)
            .Select(item => new
            {
                item.TotalPages,
                item.TotalChapters,
                item.MangaId,
                item.VolumeNumber,
                item.CurrentPage,
                item.CurrentChapter,
            })
            .FirstOrDefaultAsync(ct);

        if (volume is null)
        {
            return Result.Failure(Error.NotFound($"Volume '{command.VolumeId}' was not found."));
        }

        var currentPage = command.CurrentPage is { } requestedPage
            ? MangaVolume.Clamp(requestedPage, volume.TotalPages)
            : (int?)null;

        var currentChapter = command.CurrentChapter is { } requestedChapter
            ? MangaVolume.Clamp(requestedChapter, volume.TotalChapters)
            : (int?)null;

        // nextPage/nextChapter fall back to the stored value, so writing both is a no-op for the
        // counter the caller did not touch and keeps the whole stepper write to a single UPDATE.
        var nextPage = currentPage ?? volume.CurrentPage;
        var nextChapter = currentChapter ?? volume.CurrentChapter;

        var newStatus = MangaVolume.ResolveStatus(
            nextPage, volume.TotalPages, nextChapter, volume.TotalChapters);

        await db.MangaVolumes
            .Where(item => item.Id == command.VolumeId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(item => item.CurrentPage, nextPage)
                .SetProperty(item => item.CurrentChapter, nextChapter)
                .SetProperty(item => item.Status, newStatus), ct);

        if (volume.MangaId != Guid.Empty)
        {
            await db.Manga
                .Where(item => item.Id == volume.MangaId)
                .ExecuteUpdateAsync(
                    s => (currentChapter is { } chapter
                        ? s.SetProperty(item => item.CurrentChapter, chapter)
                        : s)
                    .SetProperty(item => item.CurrentVolume, volume.VolumeNumber),
                    ct);
        }

        return Result.Success();
    }
}
