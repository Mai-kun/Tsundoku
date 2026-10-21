using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Settings.ApiTokens;

public interface IGetApiTokensHandler
{
    Task<Result<IReadOnlyList<ApiTokenDto>>> HandleAsync(CancellationToken ct);
}

public sealed class GetApiTokensHandler(AppDbContext db) : IGetApiTokensHandler
{
    public async Task<Result<IReadOnlyList<ApiTokenDto>>> HandleAsync(CancellationToken ct)
    {
        var tokens = await db.ApiTokens
            .AsNoTracking()
            .OrderByDescending(t => t.CreatedAt)
            .Select(t => new ApiTokenDto(
                t.Id,
                t.Name,
                t.TokenPrefix,
                t.CreatedAt,
                t.LastUsedAt,
                t.ExpiresAt))
            .ToListAsync(ct);

        return Result<IReadOnlyList<ApiTokenDto>>.Success(tokens);
    }
}
