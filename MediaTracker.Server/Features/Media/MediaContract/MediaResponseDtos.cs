using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.MediaContract;

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

    public int? ReleaseYear { get; init; }

    /// <summary>Where the user watched/read it. Free text or one of the known sites.</summary>
    public string? WatchedOn { get; init; }

    public DateTime? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    public string? CoverUrl { get; init; }

    public required DateTime CreatedAt { get; init; }

    /// <summary>Feeds the cover cache-buster; the tick count is not SQL-translatable.</summary>
    public DateTime UpdatedAt { get; init; }

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

    /// <summary>manga / manhwa / manhua / oel. Null when no source could tell.</summary>
    public string? MangaFormat { get; init; }

    public int? TotalEpisodesCount { get; init; }

    public string? Network { get; init; }

    public int? TotalEpisodesWatched { get; init; }

    public int? SeasonsCount { get; init; }

    public string? ExternalId { get; init; }

    public string? ExternalSource { get; init; }

    public double? ExternalRating { get; init; }

    public int? ExternalRatingVotes { get; init; }

    public string? TranslationLanguage { get; init; }

    public string? Genres { get; init; }

    public string? Tags { get; init; }

    public string? UserPlatform { get; init; }
}

public sealed record MediaDetailDto : MediaListDto
{
    /// <summary>
    /// Populated field-by-field from the entity by <see cref="MediaResponseMapper.ToDetailDto"/>
    /// rather than copied from a list DTO, because the list shape no longer carries these values.
    /// </summary>
    public MediaDetailDto()
    {
    }

    public string? Notes { get; init; }

    public string? ExternalRatingsJson { get; init; }

    public string? TranslatedSynopsis { get; init; }

    public string? UnlockedAchievements { get; init; }

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
                MangaFormat = manga.Format,
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
        var detail = CreateDetailDto(item);

        return item switch
        {
            TvShow show => detail with
            {
                Seasons = [.. (show.Seasons ?? []).OrderBy(season => season.SeasonNumber).Select(ToDto)],
            },
            Manga manga => detail with
            {
                Volumes = [.. (manga.Volumes ?? []).OrderBy(volume => volume.VolumeNumber).Select(ToDto)],
            },
            _ => detail,
        };
    }

    /// <summary>
    /// The list projection plus the fields only the detail screen renders. Built from the entity via
    /// the shared type switch rather than copied from a list DTO, because the list shape no longer
    /// carries notes, the raw ratings JSON, the translated synopsis or the achievements JSON.
    /// </summary>
    private static MediaDetailDto CreateDetailDto(MediaItem item)
    {
        var listFields = ToListDto(item);

        return new MediaDetailDto
        {
            Id = listFields.Id,
            Type = listFields.Type,
            Title = listFields.Title,
            Status = listFields.Status,
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
        ReleaseYear = item.ReleaseYear,
        WatchedOn = item.WatchedOn,
        EndDate = item.EndDate,
        ReleaseStatus = item.ReleaseStatus,
        CoverUrl = item.CoverUrl != null ? $"{item.CoverUrl}?v={item.UpdatedAt.Ticks}" : null,
        CreatedAt = item.CreatedAt,
        UpdatedAt = item.UpdatedAt,
        FranchiseId = item.FranchiseId,
        FranchiseName = item.Franchise?.Name,
        FranchiseOrder = item.FranchiseOrder,
        ExternalId = item.ExternalId,
        ExternalSource = item.ExternalSource,
        ExternalRating = item.ExternalRating,
        ExternalRatingVotes = item.ExternalRatingVotes,
        TranslationLanguage = item.TranslationLanguage,
        Genres = item.Genres,
        Tags = item.Tags,
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
