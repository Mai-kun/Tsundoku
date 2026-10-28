using System.Data;
using Dapper;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Media.GetMediaDetail;

public sealed record GetMediaDetailQuery(Guid Id);

/// <summary>
/// The detail screen. Read-only by contract: no change tracker and no write.
/// </summary>
public interface IGetMediaDetailHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(GetMediaDetailQuery query, CancellationToken ct);
}

public sealed class GetMediaDetailHandler(AppDbContext db) : IGetMediaDetailHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(GetMediaDetailQuery query, CancellationToken ct)
    {
        var item = await db.LoadMediaItemAsync(query.Id, ct);
        Console.WriteLine($"DEBUG: LoadMediaItemAsync returned {(item == null ? "null" : item.GetType().Name + " Id=" + item.Id)}");

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{query.Id}' was not found."));
        }

        try
        {
            return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
        }
        catch (Exception ex)
        {
            return Result<MediaDetailDto>.Failure(Error.Unavailable(ex.Message));
        }
    }
}
