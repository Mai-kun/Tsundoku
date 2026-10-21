namespace MediaTracker.Server.Features.Settings.ApiTokens;

public sealed record ApiTokenDto(
    Guid Id,
    string Name,
    string TokenPrefix,
    DateTime CreatedAt,
    DateTime? LastUsedAt,
    DateTime? ExpiresAt);

public sealed record CreateApiTokenRequest(
    string Name,
    int? ExpiresInDays);

public sealed record CreatedApiTokenResponse(
    Guid Id,
    string Name,
    string TokenPrefix,
    string RawToken);
