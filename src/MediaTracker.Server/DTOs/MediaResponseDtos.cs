using System.Diagnostics.CodeAnalysis;
using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public record MediaListDto
{
    public required Guid Id { get; init; }

    public required string Type { get; init; }

    public required string Title { get; init; }

    public required MediaStatus Status { get; init; }

    public int? Score { get; init; }

    public DateTime? StartedAt { get; init; }

    public DateTime? FinishedAt { get; init; }

    public DateTime? ReleaseDate { get; init; }

    public DateTime? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    public string? Notes { get; init; }

    public string? CoverUrl { get; init; }

    public required DateTime CreatedAt { get; init; }

    public Guid? FranchiseId { get; init; }

    public string? FranchiseName { get; init; }

    public int? FranchiseOrder { get; init; }

    public string? Platform { get; init; }

    public int? HoursPlayed { get; init; }

    public string? Author { get; init; }

    public int? CurrentPage { get; init; }

    public int? TotalPages { get; init; }

    public int? CurrentChapter { get; init; }

    public int? TotalChapters { get; init; }

    public int? CurrentVolume { get; init; }

    public int? TotalVolumes { get; init; }

    public int? DurationMinutes { get; init; }

    public string? Director { get; init; }

    public bool? IsAnime { get; init; }

    public string? Studio { get; init; }

    public string? RomajiTitle { get; init; }

    public string? Network { get; init; }

    public int? TotalEpisodesCount { get; init; }

    public int? TotalEpisodesWatched { get; init; }

    public int? SeasonsCount { get; init; }

    public string? ExternalId { get; init; }

    public string? ExternalSource { get; init; }

    public double? ExternalRating { get; init; }

    public int? ExternalRatingVotes { get; init; }

    public string? ExternalRatingsJson { get; init; }

    public string? TranslatedSynopsis { get; init; }

    public string? TranslationLanguage { get; init; }

    public string? Genres { get; init; }

    public string? Tags { get; init; }

    public string? UnlockedAchievements { get; init; }

    public string? UserPlatform { get; init; }
}

public sealed record MediaDetailDto : MediaListDto
{
    [SetsRequiredMembers]
    public MediaDetailDto(MediaListDto source) : base(source)
    {
    }

    public IReadOnlyList<TvSeasonDto>? Seasons { get; init; }

    public IReadOnlyList<MangaVolumeDto>? Volumes { get; init; }
}

public sealed record MangaVolumeDto
{
    public required Guid Id { get; init; }

    public required int VolumeNumber { get; init; }

    public required string Title { get; init; }

    public string? CoverUrl { get; init; }

    public required int CurrentPage { get; init; }

    public required int TotalPages { get; init; }

    public required int CurrentChapter { get; init; }

    public required int TotalChapters { get; init; }

    public required MediaStatus Status { get; init; }

    public int? Score { get; init; }

    public string? Notes { get; init; }

    public DateTime? ReleaseDate { get; init; }

    public required Guid MangaId { get; init; }
}

public sealed record TvSeasonDto
{
    public required Guid Id { get; init; }

    public required int SeasonNumber { get; init; }

    public required string Title { get; init; }

    public string? CoverUrl { get; init; }

    public required int CurrentEpisode { get; init; }

    public required int TotalEpisodes { get; init; }

    public required MediaStatus Status { get; init; }

    public int? Score { get; init; }

    public string? Notes { get; init; }

    public DateTime? AirDate { get; init; }

    public string? EpisodesData { get; init; }

    public required Guid TvShowId { get; init; }
}

public static class MediaResponseMapper
{
    public static MediaListDto ToListDto(MediaItem item)
    {
        var dto = CreateBaseDto(item, GetType(item));

        return item switch
        {
            VideoGame game => dto with
            {
                Platform = game.Platform,
                HoursPlayed = game.HoursPlayed,
            },
            Book book => dto with
            {
                Author = book.Author,
                CurrentPage = book.CurrentPage,
                TotalPages = book.TotalPages,
            },
            Manga manga => dto with
            {
                Author = manga.Author,
                RomajiTitle = manga.RomajiTitle,
                CurrentVolume = manga.CurrentVolume,
                TotalVolumes = manga.TotalVolumes ?? (manga.Volumes?.Count > 0 ? manga.Volumes.Count : null),
                CurrentChapter = manga.CurrentChapter,
                TotalChapters = manga.TotalChapters ?? (manga.Volumes?.Count > 0 ? manga.Volumes.Sum(v => v.TotalChapters) : null),
                TotalPages = manga.Volumes?.Count > 0 ? manga.Volumes.Sum(v => v.TotalPages) : null,
            },
            Movie movie => dto with
            {
                DurationMinutes = movie.DurationMinutes,
                Director = movie.Director,
                IsAnime = movie.IsAnime,
                Studio = movie.Studio,
                RomajiTitle = movie.RomajiTitle,
            },
            TvShow show => dto with
            {
                DurationMinutes = show.EpisodeDurationMinutes,
                IsAnime = show.IsAnime,
                Studio = show.Studio,
                RomajiTitle = show.RomajiTitle,
                Network = show.Network,
                TotalEpisodesCount = show.TotalEpisodesCount,
                TotalEpisodesWatched = show.TotalEpisodesWatched,
                SeasonsCount = show.Seasons?.Count ?? 0,
            },
            _ => throw new InvalidOperationException($"Unsupported media item '{item.GetType().Name}'."),
        };
    }

    public static MediaDetailDto ToDetailDto(MediaItem item)
    {
        var detail = new MediaDetailDto(ToListDto(item));

        return item switch
        {
            TvShow show => detail with
            {
                Seasons = (show.Seasons ?? [])
                    .OrderBy(season => season.SeasonNumber)
                    .Select(ToDto)
                    .ToArray(),
            },
            Manga manga => detail with
            {
                Volumes = (manga.Volumes ?? [])
                    .OrderBy(volume => volume.VolumeNumber)
                    .Select(ToDto)
                    .ToArray(),
            },
            _ => detail,
        };
    }

    public static MangaVolumeDto ToDto(MangaVolume volume) => new()
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

    private static MediaListDto CreateBaseDto(MediaItem item, string type) => new()
    {
        Id = item.Id,
        Type = type,
        Title = item.Title,
        Status = item.Status,
        Score = item.Score,
        StartedAt = item.StartedAt,
        FinishedAt = item.FinishedAt,
        ReleaseDate = item.ReleaseDate,
        EndDate = item.EndDate,
        ReleaseStatus = item.ReleaseStatus,
        Notes = item.Notes,
        CoverUrl = item.CoverUrl != null ? $"{item.CoverUrl}?v={item.UpdatedAt.Ticks}" : null,
        CreatedAt = item.CreatedAt,
        FranchiseId = item.FranchiseId,
        FranchiseName = item.Franchise?.Name,
        FranchiseOrder = item.FranchiseOrder,
        ExternalId = item.ExternalId,
        ExternalSource = item.ExternalSource,
        ExternalRating = item.ExternalRating,
        ExternalRatingVotes = item.ExternalRatingVotes,
        ExternalRatingsJson = item.ExternalRatingsJson,
        TranslatedSynopsis = item.TranslatedSynopsis,
        TranslationLanguage = item.TranslationLanguage,
        Genres = item.Genres,
        Tags = item.Tags,
        UnlockedAchievements = item.UnlockedAchievements,
        UserPlatform = item.UserPlatform,
    };

    public static string GetType(MediaItem item) => item switch
    {
        VideoGame => "game",
        Book => "book",
        Manga => "manga",
        Movie => "movie",
        TvShow => "tvshow",
        _ => throw new InvalidOperationException($"Unsupported media item '{item.GetType().Name}'."),
    };

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
}
