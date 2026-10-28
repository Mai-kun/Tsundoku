using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Settings.ApiTokens;

public interface IRevokeApiTokenHandler
{
    Task<Result> HandleAsync(Guid id, CancellationToken ct);
}

public sealed class RevokeApiTokenHandler(AppDbContext db) : IRevokeApiTokenHandler
{
    public async Task<Result> HandleAsync(Guid id, CancellationToken ct)
    {
        var rows = await db.DeleteApiTokenAsync(id, ct);
        if (rows == 0)
        {
            return Result.Failure(Error.NotFound("API token not found."));
        }

        return Result.Success();
    }
}
