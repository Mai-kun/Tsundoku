using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.DeleteMedia;

public sealed record DeleteMediaCommand(Guid Id);

public interface IDeleteMediaHandler
{
    Task<Result> HandleAsync(DeleteMediaCommand command, CancellationToken ct);
}

public sealed class DeleteMediaHandler(
    AppDbContext db,
    IImageStorageService imageStorage,
    IMemoryCache cache) : IDeleteMediaHandler
{
    public async Task<Result> HandleAsync(DeleteMediaCommand command, CancellationToken ct)
    {
        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == command.Id, ct);

        if (item is null)
        {
            return Result.Failure(Error.NotFound($"Media item '{command.Id}' was not found."));
        }

        imageStorage.DeleteCover(item.CoverUrl);
        imageStorage.DeleteMediaFolder(item.Id);

        db.MediaItems.Remove(item);
        await db.SaveChangesAsync(ct);
        cache.Remove(AdvancedStatsCalculator.CacheKey);

        return Result.Success();
    }
}
