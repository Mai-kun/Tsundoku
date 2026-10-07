using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import;

public sealed record ParsedMediaItemDto(
    string Title, string Type, MediaStatus Status, int? Score = null,
    int? CurrentProgress = null, int? TotalCount = null, string? Author = null,
    int? ReleaseYear = null, DateTime? WatchedAt = null, string? ExternalId = null,
    string? ExternalSource = null, int? CurrentVolumes = null, int? TotalVolumes = null);

public sealed record ImportResultDto(int TotalFound, int ImportedCount, int SkippedDuplicates, Guid? TargetListId, string? TargetListName);

public sealed record SteamImportRequest(string? SteamId = null, string? ProfileUrl = null, bool SkipDuplicates = true, Guid? TargetListId = null, string? NewListName = null, string? SteamApiKey = null);

public sealed record ImportFileRequest(IFormFile File, string Provider, bool SkipDuplicates = true, Guid? TargetListId = null, string? NewListName = null);
