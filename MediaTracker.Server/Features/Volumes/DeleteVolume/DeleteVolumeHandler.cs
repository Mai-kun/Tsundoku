using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Volumes.DeleteVolume;

public sealed record DeleteVolumeCommand(Guid VolumeId);

public interface IDeleteVolumeHandler
{
    Task<Result> HandleAsync(DeleteVolumeCommand command, CancellationToken ct);
}

public sealed class DeleteVolumeHandler(AppDbContext db) : IDeleteVolumeHandler
{
    public async Task<Result> HandleAsync(DeleteVolumeCommand command, CancellationToken ct)
    {
        var volume = await db.MangaVolumes.SingleOrDefaultAsync(item => item.Id == command.VolumeId, ct);
        if (volume is null)
        {
            return Result.Failure(Error.NotFound($"Volume '{command.VolumeId}' was not found."));
        }

        db.MangaVolumes.Remove(volume);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
