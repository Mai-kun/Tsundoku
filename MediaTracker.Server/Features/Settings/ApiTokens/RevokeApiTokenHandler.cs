using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Settings.ApiTokens;

public interface IRevokeApiTokenHandler
{
    Task<Result> HandleAsync(Guid id, CancellationToken ct);
}

public sealed class RevokeApiTokenHandler(AppDbContext db) : IRevokeApiTokenHandler
{
    public async Task<Result> HandleAsync(Guid id, CancellationToken ct)
    {
        var token = await db.ApiTokens.FirstOrDefaultAsync(t => t.Id == id, ct);
        if (token is null)
        {
            return Result.Failure(Error.NotFound("API token not found."));
        }

        db.ApiTokens.Remove(token);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
