namespace MediaTracker.Server.Features.System.Updates;

public sealed record UpdateCheckResultDto(
    string CurrentVersion,
    string? LatestVersion,
    bool IsUpdateAvailable,
    bool CanSelfUpdate,
    string? ReleaseTitle,
    string? ReleaseNotes,
    string? PublishedAt,
    string? ReleaseUrl,
    string? DownloadUrl,
    long? AssetSizeBytes);
