using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Features.Settings.SaveSourceKey;
using MediaTracker.Server.Features.System.GetSources;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.Settings.GetSourceKeyStatus;

public sealed record GetSourceKeyStatusQuery(string SourceId);

/// <summary>
/// Reports whether a credential is stored for a source without ever returning
/// the secret itself (only the masked form). Import-only sources (MangaLib)
/// have no provider entry, so the sources list endpoint cannot carry this.
/// </summary>
public interface IGetSourceKeyStatusHandler
{
    Task<Result<SaveSourceKeyResponse>> HandleAsync(GetSourceKeyStatusQuery query, CancellationToken ct);
}

public sealed class GetSourceKeyStatusHandler(
    IOptions<ExternalApiOptions> options)
    : IGetSourceKeyStatusHandler
{
    public Task<Result<SaveSourceKeyResponse>> HandleAsync(GetSourceKeyStatusQuery query, CancellationToken ct)
    {
        var normalizedId = query.SourceId.Trim().ToLowerInvariant();
        var key = options.Value.GetKey(normalizedId) ?? string.Empty;
        var hasKey = !string.IsNullOrWhiteSpace(key);
        return Task.FromResult(Result<SaveSourceKeyResponse>.Success(
            new SaveSourceKeyResponse(true, hasKey, ApiKeyMask.Mask(key))));
    }
}
