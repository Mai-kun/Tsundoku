using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;

namespace MediaTracker.Server.Services.Media;

public static class MediaItemFactory
{
    public static MediaItem CreateEntity(CreateMediaRequest request)
    {
        MediaItem item = request.Type.Trim().ToLowerInvariant() switch
        {
            "game" => new VideoGame
            {
                Platform = request.Platform ?? string.Empty,
                HoursPlayed = request.HoursPlayed,
                Title = request.Title,
            },
            "book" => new Book
            {
                Author = request.Author ?? string.Empty,
                TotalPages = request.TotalPages ?? 0,
                Title = request.Title,
            },
            "manga" => new Manga
            {
                Author = request.Author,
                RomajiTitle = request.RomajiTitle,
                TotalVolumes = request.TotalVolumes,
                TotalChapters = request.TotalChapters,
                CurrentVolume = request.CurrentVolume ?? 0,
                Volumes = request.Volumes?
                    .Select(volume => new MangaVolume
                    {
                        VolumeNumber = volume.VolumeNumber,
                        Title = volume.Title,
                        CoverUrl = volume.CoverUrl,
                        TotalPages = volume.TotalPages,
                        CurrentPage = volume.CurrentPage,
                        TotalChapters = volume.TotalChapters,
                        CurrentChapter = volume.CurrentChapter,
                        Status = volume.Status,
                        Score = volume.Score,
                        Notes = volume.Notes,
                        ReleaseDate = volume.ReleaseDate,
                    })
                    .ToList() ?? [],
                Title = request.Title,
            },
            "movie" => new Movie
            {
                DurationMinutes = request.DurationMinutes ?? 0,
                Director = request.Director,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                RomajiTitle = request.RomajiTitle,
                Title = request.Title,
            },
            "tvshow" => new TvShow
            {
                Network = request.Network,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                RomajiTitle = request.RomajiTitle,
                EpisodeDurationMinutes = request.EpisodeDurationMinutes ?? request.DurationMinutes,
                Seasons = request.Seasons?
                    .Select(season => new TvSeason
                    {
                        SeasonNumber = season.SeasonNumber,
                        Title = season.Title,
                        CoverUrl = season.CoverUrl,
                        TotalEpisodes = season.TotalEpisodes,
                        Status = season.Status,
                        Score = season.Score,
                        Notes = season.Notes,
                        AirDate = season.AirDate,
                        EpisodesData = season.EpisodesData,
                    })
                    .ToList() ?? [],
                Title = request.Title,
            },
            _ => throw new InvalidOperationException($"Unsupported media type '{request.Type}'."),
        };

        item.Status = request.Status;
        item.Score = request.Score;
        item.CoverUrl = request.CoverUrl;
        item.Notes = request.Notes;
        item.FranchiseId = request.FranchiseId;
        item.FranchiseOrder = request.FranchiseOrder;
        item.ExternalId = request.ExternalId;
        item.ExternalSource = request.ExternalSource;
        item.ExternalRating = request.ExternalRating;
        item.ExternalRatingVotes = request.ExternalRatingVotes;
        item.ExternalRatingsJson = request.ExternalRatingsJson;
        item.ReleaseDate = request.ReleaseDate;
        item.EndDate = request.EndDate;
        item.ReleaseStatus = !string.IsNullOrWhiteSpace(request.ReleaseStatus)
            ? request.ReleaseStatus
            : ComputeReleaseStatusFromDates(request.ReleaseDate, request.EndDate);

        return item;
    }

    public static string? ComputeReleaseStatusFromDates(DateTime? releaseDate, DateTime? endDate)
    {
        var now = DateTime.UtcNow.Date;
        if (endDate is { } end && end <= now)
        {
            return "FINISHED";
        }
        if (releaseDate is { } start)
        {
            if (start > now)
            {
                return "NOT_YET_RELEASED";
            }
            return "RELEASING";
        }
        return null;
    }
}
