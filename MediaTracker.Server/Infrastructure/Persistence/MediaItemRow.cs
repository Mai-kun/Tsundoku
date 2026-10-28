using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Flat row mirroring every column of the <c>MediaItems</c> table. Dapper.AOT cannot materialise the
/// abstract TPH <see cref="MediaItem"/> hierarchy directly, so queries read into this row and
/// <see cref="ToEntity"/> reconstructs the correct concrete subclass with every field intact.
/// </summary>
public sealed class MediaItemRow
{
    public string Id { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public int Status { get; set; }
    public int? Score { get; set; }
    public string? DetailedScoreJson { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? FinishedAt { get; set; }
    public DateTime? LastActivityAt { get; set; }
    public string? Notes { get; set; }
    public string? DropReason { get; set; }
    public string? DropNotes { get; set; }
    public string? QuotesJson { get; set; }
    public string? Description { get; set; }
    public string? TrailerVideoId { get; set; }
    public string? CoverUrl { get; set; }
    public string? CoversJson { get; set; }
    public string? CreatorImageUrl { get; set; }
    public SyncStatus SyncStatus { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public string? FranchiseId { get; set; }
    public int? FranchiseOrder { get; set; }
    public string? ExternalId { get; set; }
    public string? ExternalSource { get; set; }
    public string? ImportSource { get; set; }
    public double? ExternalRating { get; set; }
    public int? ExternalRatingVotes { get; set; }
    public string? ExternalRatingsJson { get; set; }
    public DateTime? NextAutoRefreshAt { get; set; }
    public int AutoRefreshIntervalDays { get; set; }
    public DateTime? LastAutoRefreshedAt { get; set; }
    public DateTime? ReleaseDate { get; set; }
    public int? ReleaseYear { get; set; }
    public DateTime? EndDate { get; set; }
    public string? WatchedOn { get; set; }
    public string? ReleaseStatus { get; set; }
    public string? OriginalLanguage { get; set; }
    public string? CountryOfOrigin { get; set; }
    public string? OriginalTitle { get; set; }
    public string? CastJson { get; set; }
    public string? StaffJson { get; set; }
    public string? TranslatedSynopsis { get; set; }
    public string? TranslationLanguage { get; set; }
    public string? Genres { get; set; }
    public string? Tags { get; set; }
    public string? UnlockedAchievements { get; set; }
    public string? UserPlatform { get; set; }
    public string? RelatedMediaJson { get; set; }
    public string? PendingMatchesJson { get; set; }
    public string? RelatedSource { get; set; }
    public string? AchievementsJson { get; set; }
    public string? RecommendationsJson { get; set; }
    public DateTime? RecommendationsUpdatedAt { get; set; }
    public bool IsCustomEdited { get; set; }
    public string MediaType { get; set; } = string.Empty;

    // Manga/base fields
    public string? Author { get; set; }
    public int? CurrentPage { get; set; }
    public int? TotalPages { get; set; }
    public int? CurrentChapter { get; set; }
    public int? TotalChapters { get; set; }

    // Manga-specific (prefixed)
    public string? Manga_Author { get; set; }
    public string? Manga_RomajiTitle { get; set; }
    public string? Manga_Format { get; set; }
    public int? CurrentVolume { get; set; }
    public int? Manga_TotalVolumes { get; set; }

    // Movie fields (prefixed)
    public int? DurationMinutes { get; set; }
    public string? Director { get; set; }
    public bool? Movie_IsAnime { get; set; }
    public string? Movie_Studio { get; set; }
    public string? Movie_RomajiTitle { get; set; }

    // TvShow fields (prefixed)
    public string? Network { get; set; }
    public bool? TvShow_IsAnime { get; set; }
    public string? TvShow_Studio { get; set; }
    public string? TvShow_RomajiTitle { get; set; }
    public int? TvShow_EpisodeDurationMinutes { get; set; }

    // VideoGame fields
    public string? Platform { get; set; }
    public int? HoursPlayed { get; set; }
    public string? Studio { get; set; }

    /// <summary>
    /// Reconstructs a concrete <see cref="MediaItem"/> subclass from this row, filling every
    /// property without losing a single field.
    /// </summary>
    public MediaItem ToEntity(Franchise? franchise = null, List<TvSeason>? seasons = null, List<MangaVolume>? volumes = null)
    {
        MediaItem item = MediaType switch
        {
            SqliteSchemaInitializer.MediaTypes.Game => (MediaItem)new VideoGame
            {
                Title = Title,
                Platform = Platform ?? string.Empty,
                HoursPlayed = HoursPlayed,
                Studio = Studio,
            },
            SqliteSchemaInitializer.MediaTypes.Book => (MediaItem)new Book
            {
                Title = Title,
                Author = Author ?? string.Empty,
                TotalPages = TotalPages ?? 0,
                CurrentPage = CurrentPage ?? 0,
            },
            SqliteSchemaInitializer.MediaTypes.Manga => (MediaItem)new Manga
            {
                Title = Title,
                Author = Author ?? string.Empty,
                RomajiTitle = Manga_RomajiTitle,
                Format = Manga_Format,
                CurrentVolume = CurrentVolume ?? 0,
                TotalVolumes = Manga_TotalVolumes,
                CurrentChapter = CurrentChapter ?? 0,
                TotalChapters = TotalChapters,
                Volumes = volumes ?? [],
            },
            SqliteSchemaInitializer.MediaTypes.Movie => (MediaItem)new Movie
            {
                Title = Title,
                DurationMinutes = DurationMinutes ?? 0,
                Director = Director,
                IsAnime = Movie_IsAnime ?? false,
                Studio = Movie_Studio,
                RomajiTitle = Movie_RomajiTitle,
            },
            SqliteSchemaInitializer.MediaTypes.TvShow => (MediaItem)new TvShow
            {
                Title = Title,
                Network = Network,
                IsAnime = TvShow_IsAnime ?? false,
                Studio = TvShow_Studio,
                RomajiTitle = TvShow_RomajiTitle,
                EpisodeDurationMinutes = TvShow_EpisodeDurationMinutes,
                Seasons = seasons ?? [],
            },
            _ => throw new InvalidOperationException($"Unknown MediaType '{MediaType}' for item {Id}.")
        };

        // --- Common fields (every TPH subtype) ---
        item.Id = Guid.Parse(Id);
        item.Title = Title;
        item.SetStatus((MediaStatus)Status);
        item.Score = Score;
        item.DetailedScoreJson = DetailedScoreJson;
        item.StartedAt = StartedAt;
        item.FinishedAt = FinishedAt;
        item.LastActivityAt = LastActivityAt;
        item.Notes = Notes;
        item.DropReason = DropReason;
        item.DropNotes = DropNotes;
        item.QuotesJson = QuotesJson;
        item.Description = Description;
        item.TrailerVideoId = TrailerVideoId;
        item.CoverUrl = CoverUrl;
        item.CoversJson = CoversJson;
        item.CreatorImageUrl = CreatorImageUrl;
        item.SyncStatus = SyncStatus;
        item.CreatedAt = CreatedAt;
        item.UpdatedAt = UpdatedAt;
        item.Franchise = franchise;
        item.FranchiseId = FranchiseId is { } fid ? Guid.Parse(fid) : null;
        item.FranchiseOrder = FranchiseOrder;
        item.ExternalId = ExternalId;
        item.ExternalSource = ExternalSource;
        item.ImportSource = ImportSource;
        item.ExternalRating = ExternalRating;
        item.ExternalRatingVotes = ExternalRatingVotes;
        item.ExternalRatingsJson = ExternalRatingsJson;
        item.NextAutoRefreshAt = NextAutoRefreshAt;
        item.AutoRefreshIntervalDays = AutoRefreshIntervalDays;
        item.LastAutoRefreshedAt = LastAutoRefreshedAt;
        item.ReleaseDate = ReleaseDate;
        item.ReleaseYear = ReleaseYear;
        item.EndDate = EndDate;
        item.WatchedOn = WatchedOn;
        item.ReleaseStatus = ReleaseStatus;
        item.OriginalLanguage = OriginalLanguage;
        item.CountryOfOrigin = CountryOfOrigin;
        item.OriginalTitle = OriginalTitle;
        item.CastJson = CastJson;
        item.StaffJson = StaffJson;
        item.TranslatedSynopsis = TranslatedSynopsis;
        item.TranslationLanguage = TranslationLanguage;
        item.Genres = Genres;
        item.Tags = Tags;
        item.UnlockedAchievements = UnlockedAchievements;
        item.UserPlatform = UserPlatform;
        item.RelatedMediaJson = RelatedMediaJson;
        item.PendingMatchesJson = PendingMatchesJson;
        item.RelatedSource = RelatedSource;
        item.AchievementsJson = AchievementsJson;
        item.RecommendationsJson = RecommendationsJson;
        item.RecommendationsUpdatedAt = RecommendationsUpdatedAt;
        item.IsCustomEdited = IsCustomEdited;

        return item;
    }

    /// <summary>
    /// Maps any concrete <see cref="MediaItem"/> subclass back to a flat row for INSERT/UPDATE.
    /// </summary>
    public static MediaItemRow FromEntity(MediaItem item)
    {
        return new MediaItemRow
        {
            Id = item.Id.ToString().ToUpperInvariant(),
            Title = item.Title,
            Status = (int)item.Status,
            Score = item.Score,
            DetailedScoreJson = item.DetailedScoreJson,
            StartedAt = item.StartedAt,
            FinishedAt = item.FinishedAt,
            LastActivityAt = item.LastActivityAt,
            Notes = item.Notes,
            DropReason = item.DropReason,
            DropNotes = item.DropNotes,
            QuotesJson = item.QuotesJson,
            Description = item.Description,
            TrailerVideoId = item.TrailerVideoId,
            CoverUrl = item.CoverUrl,
            CoversJson = item.CoversJson,
            CreatorImageUrl = item.CreatorImageUrl,
            SyncStatus = item.SyncStatus,
            CreatedAt = item.CreatedAt,
            UpdatedAt = item.UpdatedAt,
            FranchiseId = item.FranchiseId?.ToString().ToUpperInvariant(),
            FranchiseOrder = item.FranchiseOrder,
            ExternalId = item.ExternalId,
            ExternalSource = item.ExternalSource,
            ImportSource = item.ImportSource,
            ExternalRating = item.ExternalRating,
            ExternalRatingVotes = item.ExternalRatingVotes,
            ExternalRatingsJson = item.ExternalRatingsJson,
            NextAutoRefreshAt = item.NextAutoRefreshAt,
            AutoRefreshIntervalDays = item.AutoRefreshIntervalDays,
            LastAutoRefreshedAt = item.LastAutoRefreshedAt,
            ReleaseDate = item.ReleaseDate,
            ReleaseYear = item.ReleaseYear,
            EndDate = item.EndDate,
            WatchedOn = item.WatchedOn,
            ReleaseStatus = item.ReleaseStatus,
            OriginalLanguage = item.OriginalLanguage,
            CountryOfOrigin = item.CountryOfOrigin,
            OriginalTitle = item.OriginalTitle,
            CastJson = item.CastJson,
            StaffJson = item.StaffJson,
            TranslatedSynopsis = item.TranslatedSynopsis,
            TranslationLanguage = item.TranslationLanguage,
            Genres = item.Genres,
            Tags = item.Tags,
            UnlockedAchievements = item.UnlockedAchievements,
            UserPlatform = item.UserPlatform,
            RelatedMediaJson = item.RelatedMediaJson,
            PendingMatchesJson = item.PendingMatchesJson,
            RelatedSource = item.RelatedSource,
            AchievementsJson = item.AchievementsJson,
            RecommendationsJson = item.RecommendationsJson,
            RecommendationsUpdatedAt = item.RecommendationsUpdatedAt,
            IsCustomEdited = item.IsCustomEdited,
            MediaType = item switch
            {
                VideoGame => SqliteSchemaInitializer.MediaTypes.Game,
                Book => SqliteSchemaInitializer.MediaTypes.Book,
                Manga => SqliteSchemaInitializer.MediaTypes.Manga,
                Movie => SqliteSchemaInitializer.MediaTypes.Movie,
                TvShow => SqliteSchemaInitializer.MediaTypes.TvShow,
                _ => throw new InvalidOperationException($"Unknown media item type '{item.GetType().Name}'.")
            },
            // Type-specific
            Author = item is Book b ? b.Author : item is Manga m ? m.Author : null,
            CurrentPage = item is Book b2 ? b2.CurrentPage : null,
            TotalPages = item is Book b3 ? b3.TotalPages : null,
            CurrentChapter = item is Manga m2 ? m2.CurrentChapter : null,
            TotalChapters = item is Manga m3 ? m3.TotalChapters : null,
            CurrentVolume = item is Manga m4 ? m4.CurrentVolume : null,
            Manga_Author = item is Manga m5 ? m5.Author : null,
            Manga_RomajiTitle = item is Manga m6 ? m6.RomajiTitle : null,
            Manga_Format = item is Manga m7 ? m7.Format : null,
            Manga_TotalVolumes = item is Manga m8 ? m8.TotalVolumes : null,
            DurationMinutes = item is Movie mv ? mv.DurationMinutes : item is TvShow tv ? tv.EpisodeDurationMinutes : null,
            Director = item is Movie mv2 ? mv2.Director : null,
            Movie_IsAnime = item is Movie mv3 ? mv3.IsAnime : item is TvShow tv2 ? tv2.IsAnime : null,
            Movie_Studio = item is Movie mv4 ? mv4.Studio : item is TvShow tv3 ? tv3.Studio : null,
            Movie_RomajiTitle = item is Movie mv5 ? mv5.RomajiTitle : item is TvShow tv4 ? tv4.RomajiTitle : null,
            Network = item is TvShow tv5 ? tv5.Network : null,
            TvShow_IsAnime = item is TvShow tv6 ? tv6.IsAnime : null,
            TvShow_Studio = item is TvShow tv7 ? tv7.Studio : null,
            TvShow_RomajiTitle = item is TvShow tv8 ? tv8.RomajiTitle : null,
            TvShow_EpisodeDurationMinutes = item is TvShow tv9 ? tv9.EpisodeDurationMinutes : null,
            Platform = item is VideoGame g ? g.Platform : null,
            HoursPlayed = item is VideoGame g2 ? g2.HoursPlayed : null,
            Studio = item is VideoGame g3 ? g3.Studio : null,
        };
    }
}
