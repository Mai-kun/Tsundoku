using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Volumes.AddVolume;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Volumes.AddVolume;

public sealed record AddVolumeCommand(Guid MangaId, CreateVolumeRequest Request);

public interface IAddVolumeHandler
{
    Task<Result<MangaVolumeDto>> HandleAsync(AddVolumeCommand command, CancellationToken ct);
}

public sealed class AddVolumeHandler(
    AppDbContext db,
    IValidator<CreateVolumeRequest> validator) : IAddVolumeHandler
{
    public async Task<Result<MangaVolumeDto>> HandleAsync(AddVolumeCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var validation = await validator.ValidateAsync(request, ct);
        if (validation.ToError() is { } validationError)
        {
            return Result<MangaVolumeDto>.Failure(validationError);
        }

        var manga = await db.Manga
            .Include(item => item.Volumes)
            .SingleOrDefaultAsync(item => item.Id == command.MangaId, ct);

        if (manga is null)
        {
            return Result<MangaVolumeDto>.Failure(Error.NotFound($"Manga '{command.MangaId}' was not found."));
        }

        var volumeNumber = request.VolumeNumber > 0 ? request.VolumeNumber : manga.Volumes.Count + 1;

        var volume = MangaVolume.CreateFrom(
            volumeNumber,
            string.IsNullOrWhiteSpace(request.Title) ? $"Volume {volumeNumber}" : request.Title,
            request.CoverUrl,
            request.TotalPages,
            request.CurrentPage,
            request.TotalChapters,
            request.CurrentChapter,
            request.Status,
            request.Score,
            request.Notes,
            request.ReleaseDate,
            manga.Id);

        manga.AddVolume(volume);
        db.MangaVolumes.Add(volume);
        await db.SaveChangesAsync(ct);

        return Result<MangaVolumeDto>.Success(MediaResponseMapper.ToDto(volume));
    }
}
