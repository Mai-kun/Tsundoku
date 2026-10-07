using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.CreateMedia;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Builds the entity a create request describes. The type switch is the only place that knows which
/// transport field feeds which subclass, so the handler stays free of mapping noise.
/// </summary>
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
            "manga" => CreateManga(request),
            "movie" => new Movie
            {
                DurationMinutes = request.DurationMinutes ?? 0,
                Director = request.Director,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                RomajiTitle = request.RomajiTitle,
                Title = request.Title,
            },
            "tvshow" => CreateTvShow(request),
            _ => throw new InvalidOperationException($"Unsupported media type '{request.Type}'."),
        };

        ApplyCommonFields(item, request);
        return item;
    }

    public static string? ComputeReleaseStatusFromDates(DateTime? releaseDate, DateTime? endDate) =>
        ReleaseStatusRules.FromDates(releaseDate, endDate);

    private static Manga CreateManga(CreateMediaRequest request)
    {
        return new Manga
        {
            Author = request.Author,
            RomajiTitle = request.RomajiTitle,
            TotalVolumes = request.TotalVolumes,
            TotalChapters = request.TotalChapters,
            CurrentVolume = request.CurrentVolume ?? 0,
            Title = request.Title,
        };
    }

    private static TvShow CreateTvShow(CreateMediaRequest request)
    {
        var show = new TvShow
        {
            Network = request.Network,
            IsAnime = request.IsAnime ?? false,
            Studio = request.Studio,
            RomajiTitle = request.RomajiTitle,
            EpisodeDurationMinutes = request.EpisodeDurationMinutes ?? request.DurationMinutes,
            Title = request.Title,
        };

        foreach (var season in request.Seasons ?? [])
        {
            show.Seasons.Add(new TvSeason
            {
                SeasonNumber = season.SeasonNumber,
                Title = season.Title,
                CoverUrl = season.CoverUrl,
                TotalEpisodes = season.TotalEpisodes,
                Score = season.Score,
                Notes = season.Notes,
                AirDate = season.AirDate,
                EpisodesData = season.EpisodesData,
                TvShowId = show.Id,
            });
        }

        return show;
    }

    private static void ApplyCommonFields(MediaItem item, CreateMediaRequest request)
    {
        item.ChangeStatus(request.Status);
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
        item.SetReleaseDate(request.ReleaseDate, request.ReleaseYear);
        item.WatchedOn = request.WatchedOn;
        item.EndDate = request.EndDate;
        item.ReleaseStatus = !string.IsNullOrWhiteSpace(request.ReleaseStatus)
            ? request.ReleaseStatus
            : ReleaseStatusRules.FromDates(request.ReleaseDate, request.EndDate);
        item.Genres = request.Genres;
        item.Tags = request.Tags;
        item.UnlockedAchievements = request.UnlockedAchievements;
        item.UserPlatform = request.UserPlatform;
    }
}
