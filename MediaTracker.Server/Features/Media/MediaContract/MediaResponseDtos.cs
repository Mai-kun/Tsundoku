using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Features.Media.GetMediaStats;

using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.Media.MediaContract;

public record MediaListDto
{
    public required Guid Id { get; init; }

    public required string Type { get; init; }

    public required string Title { get; init; }

    public required MediaStatus Status { get; init; }

    /// <summary>Whether the background enrichment of a search hit is still filling this row in.</summary>
    public required SyncStatus SyncStatus { get; init; }

    public int? Score { get; init; }

    public DateTime? StartedAt { get; init; }

    public DateTime? FinishedAt { get; init; }

    public DateTime? LastActivityAt { get; init; }

    public string? DropReason { get; init; }

    public string? DropNotes { get; init; }

    public DateTime? ReleaseDate { get; init; }

    public int? ReleaseYear { get; init; }

    /// <summary>Where the user watched/read it. Free text or one of the known sites.</summary>
    public string? WatchedOn { get; init; }

    public DateTime? EndDate { get; init; }

    public string? ReleaseStatus { get; init; }

    public string? OriginalLanguage { get; init; }

    public string? CountryOfOrigin { get; init; }

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

    /// <summary>Next scheduled background content check, so the UI can show when a title is polled.</summary>
    public DateTime? NextAutoRefreshAt { get; init; }

    /// <summary>Current adaptive interval between auto-refresh checks, in days.</summary>
    public int AutoRefreshIntervalDays { get; init; }

    public DateTime? LastAutoRefreshedAt { get; init; }

    public string? ExternalId { get; init; }

    public string? ExternalSource { get; init; }

    public string? ImportSource { get; init; }

    public double? ExternalRating { get; init; }

    public int? ExternalRatingVotes { get; init; }

    public string? TranslationLanguage { get; init; }

    /// <summary>Serialised ambiguous-match candidates; non-null only on a NeedsReview row.</summary>
    public string? PendingMatchesJson { get; init; }

    public IReadOnlyList<string> Genres { get; init; } = [];

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

    public string? DetailedScoreJson { get; init; }

    public string? QuotesJson { get; init; }

    public string? Description { get; init; }

    public string? TrailerVideoId { get; init; }

    /// <summary>Director photo or studio logo, when a provider supplied one.</summary>
    public string? CreatorImageUrl { get; init; }

    public string? ExternalRatingsJson { get; init; }

    public string? TranslatedSynopsis { get; init; }

    public string? UnlockedAchievements { get; init; }

    /// <summary>Cached related titles, so the Related tab survives a reload.</summary>
    public string? RelatedMediaJson { get; init; }

    /// <summary>The provider <see cref="RelatedMediaJson"/> was fetched from.</summary>
    public string? RelatedSource { get; init; }

    /// <summary>Cached achievements, so the game panel opens instantly on F5 without RAWG.</summary>
    public string? AchievementsJson { get; init; }

    /// <summary>Cached recommendations, written on the first explicit load.</summary>
    public string? RecommendationsJson { get; init; }

    /// <summary>When <see cref="RecommendationsJson"/> was written, so the client can show its age.</summary>
    public DateTime? RecommendationsUpdatedAt { get; init; }

    /// <summary>
    /// The cached recommendations, already parsed. Sending the blob and letting the detail screen parse
    /// it meant the browser had to know the stored shape; this way the row is the cache and the tab has
    /// a typed list to render the moment the page loads.
    /// </summary>
    public IReadOnlyList<ExternalRecommendationDto> Recommendations { get; init; } = [];

    /// <summary>
    /// The user hand-edited this row, so the refresh button has to ask before overwriting instead of
    /// discarding their work silently.
    /// </summary>
    public bool IsCustomEdited { get; init; }

    /// <summary>The title's saved cover variants, already parsed so the cover manager renders them as-is.</summary>
    public IReadOnlyList<MediaCoverItemDto> Covers { get; init; } = [];

    public IReadOnlyList<TvSeasonDto>? Seasons { get; init; }

    public IReadOnlyList<CastMemberDto> Cast { get; init; } = [];

    /// <summary>The ambiguous-match candidates, already parsed so the review UI has a typed list.</summary>
    public IReadOnlyList<ExternalMediaDto> PendingMatches { get; init; } = [];

    /// <summary>Native/romanized title, shown under the main headline on the detail screen.</summary>
    public string? OriginalTitle { get; init; }

    public string? StaffJson { get; init; }

    /// <summary>Key crew, already parsed so the overview renders it without knowing the stored shape.</summary>
    public IReadOnlyList<ExternalStaffMemberDto> Staff { get; init; } = [];

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
                Studio = game.Studio,
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
                TotalVolumes = manga.TotalVolumes,
                CurrentChapter = manga.CurrentChapter,
                TotalChapters = manga.TotalChapters,
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
            SyncStatus = listFields.SyncStatus,
            Score = listFields.Score,
            StartedAt = listFields.StartedAt,
            FinishedAt = listFields.FinishedAt,
            ReleaseDate = listFields.ReleaseDate,
            ReleaseYear = listFields.ReleaseYear,
            WatchedOn = listFields.WatchedOn,
            EndDate = listFields.EndDate,
            ReleaseStatus = listFields.ReleaseStatus,
            OriginalLanguage = listFields.OriginalLanguage,
            CountryOfOrigin = listFields.CountryOfOrigin,
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
            NextAutoRefreshAt = listFields.NextAutoRefreshAt,
            AutoRefreshIntervalDays = listFields.AutoRefreshIntervalDays,
            LastAutoRefreshedAt = listFields.LastAutoRefreshedAt,
            ExternalId = listFields.ExternalId,
            ExternalSource = listFields.ExternalSource,
            ImportSource = listFields.ImportSource,
            ExternalRating = listFields.ExternalRating,
            ExternalRatingVotes = listFields.ExternalRatingVotes,
            TranslationLanguage = listFields.TranslationLanguage,
            Genres = listFields.Genres,
            Tags = listFields.Tags,
            UserPlatform = listFields.UserPlatform,
            PendingMatchesJson = listFields.PendingMatchesJson,
            PendingMatches = MediaJsonCache.Deserialize<ExternalMediaDto>(item.PendingMatchesJson),
            Notes = item.Notes,
            DetailedScoreJson = item.DetailedScoreJson,
            QuotesJson = item.QuotesJson,
            Description = item.Description,
            TrailerVideoId = item.TrailerVideoId,
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
            Covers = MediaCoverCollection.Parse(item.CoversJson),
            Cast = MediaJsonCache.Deserialize<CastMemberDto>(item.CastJson),
            CreatorImageUrl = item.CreatorImageUrl,
            OriginalTitle = item.OriginalTitle,
            StaffJson = item.StaffJson,
            Staff = MediaJsonCache.Deserialize<ExternalStaffMemberDto>(item.StaffJson),
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
        SyncStatus = item.SyncStatus,
        Score = item.Score,
        StartedAt = item.StartedAt,
        FinishedAt = item.FinishedAt,
        LastActivityAt = item.LastActivityAt,
        DropReason = item.DropReason,
        DropNotes = item.DropNotes,
        ReleaseDate = item.ReleaseDate,
        ReleaseYear = item.ReleaseYear,
        WatchedOn = item.WatchedOn,
        EndDate = item.EndDate,
        ReleaseStatus = item.ReleaseStatus,
        OriginalLanguage = item.OriginalLanguage,
        CountryOfOrigin = item.CountryOfOrigin,
        CoverUrl = (item.CoverUrl != null && item.CoverUrl.StartsWith('/')) ? $"{item.CoverUrl}?v={item.UpdatedAt.Ticks}" : null,
        CreatedAt = item.CreatedAt,
        UpdatedAt = item.UpdatedAt,
        FranchiseId = item.FranchiseId,
        FranchiseName = item.Franchise?.Name,
        FranchiseOrder = item.FranchiseOrder,
        ExternalId = item.ExternalId,
        ExternalSource = item.ExternalSource,
        ImportSource = item.ImportSource,
        ExternalRating = item.ExternalRating,
        ExternalRatingVotes = item.ExternalRatingVotes,
        TranslationLanguage = item.TranslationLanguage,
        Genres = ParseGenres(item.Genres),
        Tags = item.Tags,
        UserPlatform = item.UserPlatform,
        PendingMatchesJson = item.PendingMatchesJson,
        NextAutoRefreshAt = item.NextAutoRefreshAt,
        AutoRefreshIntervalDays = item.AutoRefreshIntervalDays,
        LastAutoRefreshedAt = item.LastAutoRefreshedAt,
    };

    public static IReadOnlyList<string> ParseGenres(string? genres)
    {
        if (string.IsNullOrWhiteSpace(genres))
        {
            return [];
        }

        var span = genres.AsSpan().Trim();
        if (span.IsEmpty)
        {
            return [];
        }

        if (span.StartsWith("["))
        {
            try
            {
                var parsed = JsonSerializer.Deserialize(genres, AppJsonSerializerContext.Default.ListString);
                if (parsed is { Count: > 0 })
                {
                    return GenreNormalizer.NormalizeList(parsed);
                }
            }
            catch
            {
                // Fall back to comma-separated
            }
        }

        if (!span.Contains(','))
        {
            var single = GenreNormalizer.Normalize(span.ToString());
            return string.IsNullOrWhiteSpace(single) ? [] : [single];
        }

        var parts = genres.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 0 ? [] : GenreNormalizer.NormalizeList(parts);
    }

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
