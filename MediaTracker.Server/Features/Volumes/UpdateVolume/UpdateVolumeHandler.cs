using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Volumes.UpdateVolume;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Volumes.UpdateVolume;

public sealed record UpdateVolumeCommand(Guid VolumeId, UpdateVolumeRequest Request);

public interface IUpdateVolumeHandler
{
    Task<Result<MangaVolumeDto>> HandleAsync(UpdateVolumeCommand command, CancellationToken ct);
}

public sealed class UpdateVolumeHandler(
    AppDbContext db,
    IValidator<UpdateVolumeRequest> validator) : IUpdateVolumeHandler
{
    public async Task<Result<MangaVolumeDto>> HandleAsync(UpdateVolumeCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var validation = await validator.ValidateAsync(request, ct);
        if (validation.ToError() is { } validationError)
        {
            return Result<MangaVolumeDto>.Failure(validationError);
        }

        var volume = await db.MangaVolumes.SingleOrDefaultAsync(item => item.Id == command.VolumeId, ct);
        if (volume is null)
        {
            return Result<MangaVolumeDto>.Failure(Error.NotFound($"Volume '{command.VolumeId}' was not found."));
        }

        volume.ApplyEdits(request.CurrentPage, request.TotalPages, request.CurrentChapter, request.TotalChapters);

        if (request.Title is not null) volume.Title = request.Title;
        if (request.CoverUrl is not null) volume.CoverUrl = request.CoverUrl;
        if (request.Status.HasValue) volume.ApplyStatus(request.Status.Value);
        if (request.Score.HasValue) volume.Score = request.Score.Value;
        if (request.Notes is not null) volume.Notes = request.Notes;

        await db.SaveChangesAsync(ct);
        return Result<MangaVolumeDto>.Success(MediaResponseMapper.ToDto(volume));
    }
}
