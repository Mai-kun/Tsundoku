using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;

namespace MediaTracker.Server.Features.Settings.ApiTokens;

public interface ICreateApiTokenHandler
{
    Task<Result<CreatedApiTokenResponse>> HandleAsync(CreateApiTokenRequest request, CancellationToken ct);
}

public sealed class CreateApiTokenHandler(AppDbContext db) : ICreateApiTokenHandler
{
    public async Task<Result<CreatedApiTokenResponse>> HandleAsync(CreateApiTokenRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return Result<CreatedApiTokenResponse>.Failure(Error.Validation("Token name is required."));
        }

        var trimmedName = request.Name.Trim();
        if (trimmedName.Length > 100)
        {
            return Result<CreatedApiTokenResponse>.Failure(Error.Validation("Token name must not exceed 100 characters."));
        }

        if (request.ExpiresInDays is <= 0)
        {
            return Result<CreatedApiTokenResponse>.Failure(Error.Validation("Expires in days must be greater than zero."));
        }

        var (rawToken, prefix, hash) = ApiTokenHelper.GenerateToken();
        var expiresAt = request.ExpiresInDays.HasValue
            ? DateTime.UtcNow.AddDays(request.ExpiresInDays.Value)
            : (DateTime?)null;

        var tokenEntity = new ApiToken
        {
            Id = Guid.NewGuid(),
            Name = trimmedName,
            TokenPrefix = prefix,
            TokenHash = hash,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = expiresAt
        };

        await db.CreateApiTokenAsync(tokenEntity, ct);

        return Result<CreatedApiTokenResponse>.Success(new CreatedApiTokenResponse(
            tokenEntity.Id,
            tokenEntity.Name,
            tokenEntity.TokenPrefix,
            rawToken));
    }
}
