using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.Media.MediaContract;

/// <summary>
/// The detail shape: the list projection plus the fields only the detail screen renders. Built from
/// the entity through the shared mapper rather than copied from a list DTO, because the list shape
/// deliberately does not carry notes, the raw ratings JSON, the translated synopsis or achievements.
/// </summary>
public static class MediaDetailProjection
{
    public static MediaDetailDto ToDetailDto(MediaItem item) => item switch
    {
        TvShow show => Create(item) with
        {
            Seasons = [.. show.Seasons.OrderBy(season => season.SeasonNumber).Select(ToDto)],
        },
        Manga manga => Create(item) with
        {
            Volumes = [.. manga.Volumes.OrderBy(volume => volume.VolumeNumber).Select(ToDto)],
        },
        _ => Create(item),
    };

    private static MediaDetailDto Create(MediaItem item)
    {
        var listFields = MediaResponseMapper.ToListDto(item);

        return new MediaDetailDto
        {
            Id = listFields.Id,
            Type = listFields.Type,
            Title = listFields.Title,
            Status = listFields.Status,
            SyncStatus = listFields.SyncStatus,
            Score = listFields.Score,
            StartedAt = listFields.StartedAt,
            FinishedAt = listFields.FinishedAt,
            ReleaseDate = listFields.ReleaseDate,
            ReleaseYear = listFields.ReleaseYear,
            WatchedOn = listFields.WatchedOn,
            EndDate = listFields.EndDate,
            ReleaseStatus = listFields.ReleaseStatus,
            CoverUrl = listFields.CoverUrl,
            CreatedAt = listFields.CreatedAt,
            UpdatedAt = listFields.UpdatedAt,
            FranchiseId = listFields.FranchiseId,
            FranchiseName = listFields.FranchiseName,
            FranchiseOrder = listFields.FranchiseOrder,
            Platform = listFields.Platform,
            HoursPlayed = listFields.HoursPlayed,
            Author = listFields.Author,
            CurrentPage = listFields.CurrentPage,
            TotalPages = listFields.TotalPages,
            CurrentChapter = listFields.CurrentChapter,
            TotalChapters = listFields.TotalChapters,
            CurrentVolume = listFields.CurrentVolume,
            TotalVolumes = listFields.TotalVolumes,
            DurationMinutes = listFields.DurationMinutes,
            Director = listFields.Director,
            IsAnime = listFields.IsAnime,
            Studio = listFields.Studio,
            RomajiTitle = listFields.RomajiTitle,
            MangaFormat = listFields.MangaFormat,
            TotalEpisodesCount = listFields.TotalEpisodesCount,
            Network = listFields.Network,
            TotalEpisodesWatched = listFields.TotalEpisodesWatched,
            SeasonsCount = listFields.SeasonsCount,
            ExternalId = listFields.ExternalId,
            ExternalSource = listFields.ExternalSource,
            ExternalRating = listFields.ExternalRating,
            ExternalRatingVotes = listFields.ExternalRatingVotes,
            TranslationLanguage = listFields.TranslationLanguage,
            Genres = listFields.Genres,
            Tags = listFields.Tags,
            UserPlatform = listFields.UserPlatform,
            Notes = item.Notes,
            ExternalRatingsJson = item.ExternalRatingsJson,
            TranslatedSynopsis = item.TranslatedSynopsis,
            UnlockedAchievements = item.UnlockedAchievements,
            RelatedMediaJson = item.RelatedMediaJson,
            RelatedSource = item.RelatedSource,
            AchievementsJson = item.AchievementsJson,
            RecommendationsJson = item.RecommendationsJson,
            RecommendationsUpdatedAt = item.RecommendationsUpdatedAt,
            Recommendations = MediaJsonCache.Deserialize<ExternalRecommendationDto>(item.RecommendationsJson),
            IsCustomEdited = item.IsCustomEdited,
        };
    }

    private static TvSeasonDto ToDto(TvSeason season) => new()
    {
        Id = season.Id,
        SeasonNumber = season.SeasonNumber,
        Title = season.Title,
        CoverUrl = season.CoverUrl,
        CurrentEpisode = season.CurrentEpisode,
        TotalEpisodes = season.TotalEpisodes,
        Status = season.Status,
        Score = season.Score,
        Notes = season.Notes,
        AirDate = season.AirDate,
        EpisodesData = season.EpisodesData,
        TvShowId = season.TvShowId,
    };

    private static MangaVolumeDto ToDto(MangaVolume volume) => new()
    {
        Id = volume.Id,
        VolumeNumber = volume.VolumeNumber,
        Title = volume.Title,
        CoverUrl = volume.CoverUrl,
        CurrentPage = volume.CurrentPage,
        TotalPages = volume.TotalPages,
        CurrentChapter = volume.CurrentChapter,
        TotalChapters = volume.TotalChapters,
        Status = volume.Status,
        Score = volume.Score,
        Notes = volume.Notes,
        ReleaseDate = volume.ReleaseDate,
        MangaId = volume.MangaId,
    };
}
