using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>Filters and ordering for the media list endpoint.</summary>
public sealed record GetMediaListQuery(
    string? Type = null,
    MediaStatus? Status = null,
    bool? IsAnime = null,
    string? Search = null,
    string? SortBy = "createdAt",
    string? SortOrder = "desc",
    int? Limit = null,
    int? Offset = null);
