using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.MediaContract;

namespace MediaTracker.Server.Features.Media.GetMediaList;

/// <summary>
/// The single SQL projection behind the library lists. Every scalar the cards render is selected
/// here, and the season/volume collections become aggregates in the database instead of a graph the
/// change tracker has to build.
/// </summary>
public static class MediaListProjection
{
    public static IQueryable<MediaListQuery.MediaListRow> ProjectRows(IQueryable<MediaItem> source) =>
        source.Select(item => new MediaListQuery.MediaListRow(ToDto(item), item.UpdatedAt));

    public static MediaListDto ToDto(MediaItem item) => new()
    {
        Id = item.Id,
        Type = item is VideoGame ? "game"
            : item is Book ? "book"
            : item is Manga ? "manga"
            : item is Movie ? "movie"
            : "tvshow",
        Title = item.Title,
        Status = item.Status,
        Score = item.Score,
        StartedAt = item.StartedAt,
        FinishedAt = item.FinishedAt,
        ReleaseDate = item.ReleaseDate,
        ReleaseYear = item.ReleaseYear,
        WatchedOn = item.WatchedOn,
        EndDate = item.EndDate,
        ReleaseStatus = item.ReleaseStatus,
        CoverUrl = item.CoverUrl,
        CreatedAt = item.CreatedAt,
        UpdatedAt = item.UpdatedAt,
        FranchiseId = item.FranchiseId,
        FranchiseName = item.Franchise != null ? item.Franchise.Name : null,
        FranchiseOrder = item.FranchiseOrder,
        Platform = item is VideoGame ? ((VideoGame)item).Platform : null,
        HoursPlayed = item is VideoGame ? ((VideoGame)item).HoursPlayed : null,
        Author = item is Book ? ((Book)item).Author : item is Manga ? ((Manga)item).Author : null,
        CurrentPage = item is Book ? ((Book)item).CurrentPage : null,
        TotalPages = item is Book
            ? ((Book)item).TotalPages
            : item is Manga
                ? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Sum(volume => volume.TotalPages) : null)
                : null,
        CurrentChapter = item is Manga ? ((Manga)item).CurrentChapter : null,
        TotalChapters = item is Manga
            ? (((Manga)item).TotalChapters
                ?? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Sum(volume => volume.TotalChapters) : null))
            : null,
        CurrentVolume = item is Manga ? ((Manga)item).CurrentVolume : null,
        TotalVolumes = item is Manga
            ? (((Manga)item).TotalVolumes
                ?? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Count : null))
            : null,
        DurationMinutes = item is Movie
            ? ((Movie)item).DurationMinutes
            : item is TvShow
                ? ((TvShow)item).EpisodeDurationMinutes
                : null,
        Director = item is Movie ? ((Movie)item).Director : null,
        IsAnime = item is Movie ? ((Movie)item).IsAnime : item is TvShow ? ((TvShow)item).IsAnime : null,
        Studio = item is Movie ? ((Movie)item).Studio : item is TvShow ? ((TvShow)item).Studio : null,
        RomajiTitle = item is Movie
            ? ((Movie)item).RomajiTitle
            : item is TvShow
                ? ((TvShow)item).RomajiTitle
                : item is Manga ? ((Manga)item).RomajiTitle : null,
        Network = item is TvShow ? ((TvShow)item).Network : null,
        TotalEpisodesCount = item is TvShow ? ((TvShow)item).Seasons.Sum(season => season.TotalEpisodes) : null,
        TotalEpisodesWatched = item is TvShow ? ((TvShow)item).Seasons.Sum(season => season.CurrentEpisode) : null,
        SeasonsCount = item is TvShow ? ((TvShow)item).Seasons.Count : 0,
        ExternalId = item.ExternalId,
        ExternalSource = item.ExternalSource,
        ExternalRating = item.ExternalRating,
        ExternalRatingVotes = item.ExternalRatingVotes,
        TranslationLanguage = item.TranslationLanguage,
        Genres = item.Genres,
        Tags = item.Tags,
        UserPlatform = item.UserPlatform,
    };

    /// <summary>
    /// Covers are served as immutable for a year, so the cache-buster is part of the URL. The tick
    /// count cannot be produced in SQL, so it is stamped after the row materializes.
    /// </summary>
    public static MediaListDto WithCoverVersion(MediaListDto dto, DateTime updatedAt) =>
        dto.CoverUrl is null ? dto : dto with { CoverUrl = $"{dto.CoverUrl}?v={updatedAt.Ticks}" };
}
