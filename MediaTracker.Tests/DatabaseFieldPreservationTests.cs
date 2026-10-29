using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.DeleteMedia;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;
using System.Threading.Channels;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Эталонные тесты сохранности 100% полей БД. Перед переходом MediaTracker.Server с EF Core на
/// Dapper.AOT (NativeAOT) этот файл — главный контроль качества: каждый тип сущностей заполняется
/// НЕ-дефолтными значениями во ВСЕХ свойствах, проходит реальный цикл SQLite-записи и читается
/// обратно реальными хэндлерами, после чего каждое поле DTO проверяется через Assert.Equal.
/// Если маппинг Dapper потеряет колонку (включая Movie_/TvShow_/Manga_-префиксы и все *Json),
/// один из этих тестов упадёт.
/// </summary>
public sealed class DatabaseFieldPreservationTests
{
    private static readonly DateTime T1 = new(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc);
    private static readonly DateTime T2 = new(2021, 2, 3, 4, 5, 6, DateTimeKind.Utc);
    private static readonly DateTime T3 = new(2022, 3, 4, 5, 6, 7, DateTimeKind.Utc);
    private static readonly DateTime T4 = new(2023, 4, 5, 6, 7, 8, DateTimeKind.Utc);
    private static readonly DateTime T5 = new(2023, 5, 6, 7, 8, 9, DateTimeKind.Utc);
    private static readonly DateTime T6 = new(2023, 6, 7, 8, 9, 10, DateTimeKind.Utc);
    private static readonly DateTime T7 = new(2023, 7, 8, 9, 10, 11, DateTimeKind.Utc);
    private static readonly DateTime T8 = new(2023, 8, 9, 10, 11, 12, DateTimeKind.Utc);
    private static readonly DateTime T9 = new(2023, 9, 10, 11, 12, 13, DateTimeKind.Utc);
    private static readonly DateTime T10 = new(2023, 10, 11, 12, 13, 14, DateTimeKind.Utc);
    private static readonly DateTime T11 = new(2023, 11, 12, 13, 14, 15, DateTimeKind.Utc);
    private static readonly DateTime T12 = new(2023, 12, 13, 14, 15, 16, DateTimeKind.Utc);

    private static AppDbContext CreateDbContext()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"field_preservation_{Guid.NewGuid():N}.db");
        var db = new AppDbContext($"Data Source={dbPath}");
        return db;
    }

    private static string Suffix(string key) => $"{key}_{Guid.NewGuid():N}";

    // Test-side blobs (detailed score, quotes, cast ...) mix anonymous shapes, so they use a plain
    // reflection serializer here; the server side reads them back through the AOT context.
    private static readonly System.Text.Json.JsonSerializerOptions TestJsonOptions =
        new(System.Text.Json.JsonSerializerDefaults.Web);

    private static string Serialize(IReadOnlyList<object> value) =>
        System.Text.Json.JsonSerializer.Serialize(value, TestJsonOptions);

    private sealed record MediaCatalog
    {
        public required Franchise Franchise { get; init; }
        public required Movie Movie { get; init; }
        public required VideoGame Game { get; init; }
        public required Book Book { get; init; }
        public required Manga Manga { get; init; }
        public required MangaVolume MangaVolume { get; init; }
        public required TvShow TvShow { get; init; }
        public required TvSeason TvSeason { get; init; }
        public required CustomList CustomList { get; init; }
        public required CustomListItem CustomListItem { get; init; }
        public required MediaEvent MediaEvent { get; init; }
        public required AppSetting AppSetting { get; init; }
        public required ApiToken ApiToken { get; init; }
    }

    /// <summary>
    /// Заполняет КАЖДОЕ свойство КАЖДОГО типа уникальными не-дефолтными значениями и сохраняет в
    /// реальную SQLite-базу. Один хэндлер-тест = одна свежая база, чтобы тесты были независимы.
    /// </summary>
    private static async Task<MediaCatalog> SeedFullCatalogAsync(AppDbContext db)
    {
        var k = Suffix("f");

        var franchise = new Franchise
        {
            Id = Guid.NewGuid(),
            Name = $"Franchise Name {k}",
            Description = $"Franchise Description {k}",
            CoverUrl = $"/franchises/{k}.webp",
        };

        var movie = new Movie
        {
            Id = Guid.NewGuid(),
            Title = $"Movie Title {k}",
            DurationMinutes = 142,
            Director = $"Movie Director {k}",
            IsAnime = true,
            Studio = $"Movie Studio {k}",
            RomajiTitle = $"Movie Romaji {k}",
        };
        FillAllMediaItemFields(movie, k, score: 8, syncStatus: SyncStatus.NeedsReview);

        var game = new VideoGame
        {
            Id = Guid.NewGuid(),
            Title = $"Game Title {k}",
            Platform = $"PC Platform {k}",
            HoursPlayed = 55,
            Studio = $"Game Developer {k}",
        };
        FillAllMediaItemFields(game, k, score: 9, syncStatus: SyncStatus.Ready);

        var book = new Book
        {
            Id = Guid.NewGuid(),
            Title = $"Book Title {k}",
            Author = $"Book Author {k}",
            CurrentPage = 111,
            TotalPages = 222,
        };
        FillAllMediaItemFields(book, k, score: 7, syncStatus: SyncStatus.Failed);

        var mangaVolume = new MangaVolume
        {
            Id = Guid.NewGuid(),
            VolumeNumber = 2,
            Title = $"Volume Title {k}",
            CoverUrl = $"/volumes/{k}.webp",
            CurrentPage = 21,
            TotalPages = 42,
            CurrentChapter = 5,
            TotalChapters = 9,
            Status = MediaStatus.InProgress,
            Score = 6,
            Notes = $"Volume Notes {k}",
            ReleaseDate = T7,
        };

        var manga = new Manga
        {
            Id = Guid.NewGuid(),
            Title = $"Manga Title {k}",
            CurrentChapter = 5,
            TotalChapters = 12,
            Author = $"Manga Author {k}",
            RomajiTitle = $"Manga Romaji {k}",
            Format = "manhwa",
            CurrentVolume = 2,
            TotalVolumes = 4,
        };
        FillAllMediaItemFields(manga, k, score: 6, syncStatus: SyncStatus.Syncing);
        manga.Volumes.Add(mangaVolume);
        mangaVolume.Manga = manga;
        mangaVolume.MangaId = manga.Id;
        db.MangaVolumes.Add(mangaVolume);

        var tvSeason = new TvSeason
        {
            Id = Guid.NewGuid(),
            SeasonNumber = 1,
            Title = $"Season Title {k}",
            CoverUrl = $"/seasons/{k}.webp",
            CurrentEpisode = 4,
            TotalEpisodes = 12,
            Status = MediaStatus.InProgress,
            Score = 5,
            Notes = $"Season Notes {k}",
            AirDate = T6,
            EpisodesData = $"[{{\"episode\":1,\"name\":\"Episode One {k}\"}}]",
        };

        var tvShow = new TvShow
        {
            Id = Guid.NewGuid(),
            Title = $"TvShow Title {k}",
            Network = $"TvShow Network {k}",
            IsAnime = true,
            Studio = $"TvShow Studio {k}",
            RomajiTitle = $"TvShow Romaji {k}",
            EpisodeDurationMinutes = 24,
        };
        FillAllMediaItemFields(tvShow, k, score: 10, syncStatus: SyncStatus.Ready);
        tvShow.Seasons.Add(tvSeason);
        tvSeason.TvShow = tvShow;
        tvSeason.TvShowId = tvShow.Id;
        db.TvSeasons.Add(tvSeason);
        await db.SaveChangesAsync();

        foreach (var item in new MediaItem[] { movie, game, book, manga, tvShow })
        {
            item.Franchise = franchise;
            item.FranchiseId = franchise.Id;
            franchise.Items.Add(item);
        }

        var mediaEvent = new MediaEvent
        {
            Id = Guid.NewGuid(),
            MediaId = movie.Id,
            Media = movie,
            Type = MediaEventType.StatusChanged,
            OldValue = $"Event Old {k}",
            NewValue = $"Event New {k}",
            CreatedAt = T9,
        };

        var appSetting = new AppSetting
        {
            Key = $"Setting Key {k}",
            Value = $"Setting Value {k}",
            UpdatedAt = T10,
        };

        var apiToken = new ApiToken
        {
            Id = Guid.NewGuid(),
            Name = $"Token Name {k}",
            TokenHash = $"TokenHash {k}",
            TokenPrefix = $"tsk_live_{k}",
            CreatedAt = T11,
            LastUsedAt = T12,
            ExpiresAt = T8,
        };
        db.Franchises.Add(franchise);
        db.MediaItems.Add(movie);
        db.MediaItems.Add(game);
        db.MediaItems.Add(book);
        db.MediaItems.Add(manga);
        db.MediaItems.Add(tvShow);
        db.Settings.Add(appSetting);
        db.ApiTokens.Add(apiToken);
        db.MediaEvents.Add(mediaEvent);
        db.MangaVolumes.Add(mangaVolume);
        db.TvSeasons.Add(tvSeason);
        await db.SaveChangesAsync();

        // Отдельный не-аниме фильм, чтобы фильтр IsAnime=false имел что вернуть: игра и книга
        // в этот фильтр не попадают в принципе (IsAnime у них null).
        var liveAction = new Movie
        {
            Id = Guid.NewGuid(),
            Title = $"Live Action Movie {k}",
            IsAnime = false,
            Status = MediaStatus.Planned,
        };
        db.Add(liveAction);
        await db.SaveChangesAsync();

        var customList = new CustomList
        {
            Id = Guid.NewGuid(),
            Name = $"List Name {k}",
            Description = $"List Description {k}",
            Icon = "star",
            Color = "#A1B2C3",
            CreatedAt = T5,
            UpdatedAt = T4,
        };
        var customListItem = new CustomListItem
        {
            Id = Guid.NewGuid(),
            List = customList,
            ListId = customList.Id,
            MediaItem = game,
            MediaItemId = game.Id,
            Order = 3,
            AddedAt = T3,
        };
        customList.Items.Add(customListItem);
        db.CustomLists.Add(customList);
        await db.SaveChangesAsync();

        return new MediaCatalog
        {
            Franchise = franchise,
            Movie = movie,
            Game = game,
            Book = book,
            Manga = manga,
            MangaVolume = mangaVolume,
            TvShow = tvShow,
            TvSeason = tvSeason,
            CustomList = customList,
            CustomListItem = customListItem,
            MediaEvent = mediaEvent,
            AppSetting = appSetting,
            ApiToken = apiToken,
        };
    }

    /// <summary>Заполняет все наследуемые поля MediaItem; вызывается для каждого из 5 типов.</summary>
    private static void FillAllMediaItemFields(MediaItem item, string k, int score, SyncStatus syncStatus)
    {
        item.Status = MediaStatus.InProgress;
        item.Score = score;
        item.DetailedScoreJson = Serialize(new[] { new { Key = $"DetailedScore {k}", Value = score } });
        item.StartedAt = T1;
        item.FinishedAt = T2;
        item.LastActivityAt = T3;
        item.Notes = $"Notes {k}";
        item.DropReason = $"DropReason {k}";
        item.DropNotes = $"DropNotes {k}";
        item.QuotesJson = Serialize(new[] { new { Quote = $"Quote {k}" } });
        item.Description = $"Description {k}";
        item.TrailerVideoId = $"trailer-{k}";
        item.CoverUrl = $"/covers/{k}.webp";
        item.CoversJson = MediaCoverCollection.Serialize([
            new MediaCoverItemDto(
                $"cover-{k}",
                $"/media-assets/{item.Id}/covers/cover-{k}/thumb.webp",
                $"/media-assets/{item.Id}/covers/cover-{k}/original.webp",
                "custom",
                T5)
        ]);
        item.CreatorImageUrl = $"/creators/{k}.webp";
        item.SyncStatus = syncStatus;
        item.CreatedAt = T4;
        item.UpdatedAt = T5;
        item.FranchiseOrder = 3;
        item.ExternalId = $"external-id-{k}";
        item.ExternalSource = "tmdb";
        item.ImportSource = $"ImportSource {k}";
        item.ExternalRating = 7.75;
        item.ExternalRatingVotes = 123;
        item.ExternalRatingsJson = Serialize(new[] { new { Source = "tmdb", Rating = 7.75, Votes = 123 } });
        item.NextAutoRefreshAt = T7;
        item.AutoRefreshIntervalDays = 13;
        item.LastAutoRefreshedAt = T6;
        item.ReleaseDate = T8;
        item.ReleaseYear = 1987;
        item.EndDate = T9;
        item.WatchedOn = $"WatchedOn {k}";
        item.ReleaseStatus = $"ReleaseStatus {k}";
        item.OriginalLanguage = $"Language {k}";
        item.CountryOfOrigin = $"Country {k}";
        item.OriginalTitle = $"Original Title {k}";
        item.CastJson = Serialize(new[]
        {
            new CastMemberDto($"Cast Name {k}", $"Cast Character {k}", $"/cast/{k}.webp")
            {
                CharacterRole = "SUPPORTING",
                CharacterImageUrl = $"/cast/character/{k}.webp",
                VoiceActorName = $"Voice Actor {k}",
                VoiceActorImageUrl = $"/cast/va/{k}.webp",
            },
        });
        item.StaffJson = Serialize(new[]
        {
            new ExternalStaffMemberDto($"Staff Name {k}", $"Staff Role {k}", $"/staff/{k}.webp"),
        });
        item.TranslatedSynopsis = $"Translated Synopsis {k}";
        item.TranslationLanguage = $"Translation Language {k}";
        item.Genres = "Кибербезопасность, Астрофизика";
        item.Tags = $"Tag One {k}, Tag Two {k}";
        item.UnlockedAchievements = $"Achievement {k}";
        item.UserPlatform = $"UserPlatform {k}";
        item.RelatedMediaJson = Serialize(new[]
        {
            new ExternalMediaDto
            {
                ExternalId = $"related-ext-{k}",
                Title = $"Related Title {k}",
                Type = "movie",
                Rating = 8.25,
            },
        });
        item.RelatedSource = $"RelatedSource {k}";
        item.PendingMatchesJson = Serialize(new[] { new ExternalMediaDto
        {
            ExternalId = $"pending-ext-{k}",
            Title = $"Pending Match Title {k}",
            Type = "movie",
        } });
        item.AchievementsJson = Serialize(new[]
        {
            new { Name = $"Achievement Json {k}", Percent = 42 },
        });
        item.RecommendationsJson = Serialize(new[]
        {
            new ExternalRecommendationDto($"rec-id-{k}", $"Recommendation {k}", $"/rec/{k}.webp", 9.5, "tmdb"),
        });
        item.RecommendationsUpdatedAt = T10;
        item.IsCustomEdited = true;
    }

    /// <summary>Все поля MediaListDto, общие для пяти типов.</summary>
    private static void AssertBaseListFields(MediaItem e, MediaListDto d, string k)
    {
        Assert.Equal(e.Id, d.Id);
        Assert.Equal(MediaResponseMapper.GetType(e), d.Type);
        Assert.Equal(e.Title, d.Title);
        Assert.Equal(MediaStatus.InProgress, d.Status);
        Assert.Equal(e.SyncStatus, d.SyncStatus);
        Assert.Equal(e.Score, d.Score);
        Assert.Equal(T1, d.StartedAt);
        Assert.Equal(T2, d.FinishedAt);
        Assert.Equal(T3, d.LastActivityAt);
        Assert.Equal($"DropReason {k}", d.DropReason);
        Assert.Equal($"DropNotes {k}", d.DropNotes);
        Assert.Equal(T8, d.ReleaseDate);
        Assert.Equal(1987, d.ReleaseYear);
        Assert.Equal($"WatchedOn {k}", d.WatchedOn);
        Assert.Equal(T9, d.EndDate);
        Assert.Equal($"ReleaseStatus {k}", d.ReleaseStatus);
        Assert.Equal($"Language {k}", d.OriginalLanguage);
        Assert.Equal($"Country {k}", d.CountryOfOrigin);
        Assert.Equal($"/covers/{k}.webp?v={T5.Ticks}", d.CoverUrl);
        Assert.Equal(T4, d.CreatedAt);
        Assert.Equal(T5, d.UpdatedAt);
        Assert.Equal(e.FranchiseId, d.FranchiseId);
        Assert.Equal($"Franchise Name {k}", d.FranchiseName);
        Assert.Equal(3, d.FranchiseOrder);
        Assert.Equal($"external-id-{k}", d.ExternalId);
        Assert.Equal("tmdb", d.ExternalSource);
        Assert.Equal($"ImportSource {k}", d.ImportSource);
        Assert.Equal(7.75, d.ExternalRating);
        Assert.Equal(123, d.ExternalRatingVotes);
        Assert.Equal($"Translation Language {k}", d.TranslationLanguage);
        Assert.Equal($"DropReason {k}", d.DropReason);
        Assert.Equal(new[] { "Кибербезопасность", "Астрофизика" }, d.Genres);
        Assert.Equal($"Tag One {k}, Tag Two {k}", d.Tags);
        Assert.Equal($"UserPlatform {k}", d.UserPlatform);
        Assert.Equal(13, d.AutoRefreshIntervalDays);
        Assert.Equal(T7, d.NextAutoRefreshAt);
        Assert.Equal(T6, d.LastAutoRefreshedAt);
        Assert.Equal(e.PendingMatchesJson, d.PendingMatchesJson);
    }

    /// <summary>Все поля MediaDetailDto поверх списка: detail-only JSON-колонки и флаги.</summary>
    private static void AssertDetailOnlyFields(MediaItem e, MediaDetailDto d, string k)
    {
        AssertBaseListFields(e, d, k);

        Assert.Equal($"Notes {k}", d.Notes);
        Assert.Equal(e.DetailedScoreJson, d.DetailedScoreJson);
        Assert.Equal(e.QuotesJson, d.QuotesJson);
        Assert.Equal($"Description {k}", d.Description);
        Assert.Equal($"trailer-{k}", d.TrailerVideoId);
        Assert.Equal($"/creators/{k}.webp", d.CreatorImageUrl);
        Assert.Equal(e.ExternalRatingsJson, d.ExternalRatingsJson);
        Assert.Equal($"Translated Synopsis {k}", d.TranslatedSynopsis);
        Assert.Equal($"Achievement {k}", d.UnlockedAchievements);
        Assert.Equal(e.RelatedMediaJson, d.RelatedMediaJson);
        Assert.Equal($"RelatedSource {k}", d.RelatedSource);
        Assert.Equal(e.AchievementsJson, d.AchievementsJson);
        Assert.Equal(e.RecommendationsJson, d.RecommendationsJson);
        Assert.Equal(T10, d.RecommendationsUpdatedAt);
        Assert.True(d.IsCustomEdited);
        Assert.Equal($"Original Title {k}", d.OriginalTitle);
        Assert.Equal(e.StaffJson, d.StaffJson);

        var cover = Assert.Single(d.Covers);
        Assert.Equal($"cover-{k}", cover.Id);
        Assert.Equal($"/media-assets/{e.Id}/covers/cover-{k}/thumb.webp", cover.ThumbUrl);
        Assert.Equal($"/media-assets/{e.Id}/covers/cover-{k}/original.webp", cover.OriginalUrl);
        Assert.Equal("custom", cover.Source);
        Assert.Equal(T5, cover.AddedAt);

        var cast = Assert.Single(d.Cast);
        Assert.Equal($"Cast Name {k}", cast.Name);
        Assert.Equal($"Cast Character {k}", cast.Character);
        Assert.Equal($"/cast/{k}.webp", cast.PhotoUrl);
        Assert.Equal("SUPPORTING", cast.CharacterRole);
        Assert.Equal($"/cast/character/{k}.webp", cast.CharacterImageUrl);
        Assert.Equal($"Voice Actor {k}", cast.VoiceActorName);
        Assert.Equal($"/cast/va/{k}.webp", cast.VoiceActorImageUrl);

        var staff = Assert.Single(d.Staff);
        Assert.Equal($"Staff Name {k}", staff.Name);
        Assert.Equal($"Staff Role {k}", staff.Role);
        Assert.Equal($"/staff/{k}.webp", staff.ImageUrl);

        var pending = Assert.Single(d.PendingMatches);
        Assert.Equal($"pending-ext-{k}", pending.ExternalId);
        Assert.Equal($"Pending Match Title {k}", pending.Title);

        var recommendations = Assert.Single(d.Recommendations);
        Assert.Equal($"rec-id-{k}", recommendations.Id);
        Assert.Equal($"Recommendation {k}", recommendations.Title);
        Assert.Equal($"/rec/{k}.webp", recommendations.CoverUrl);
        Assert.Equal(9.5, recommendations.Rating);
        Assert.Equal("tmdb", recommendations.Source);
    }

    // ------------------------------------------------------------------
    // GetMediaDetailHandler: 5 типов, каждое поле MediaDetailDto
    // ------------------------------------------------------------------

    [Fact]
    public async Task GetMediaDetail_Movie_RoundTripsEveryField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Movie.Title);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(catalog.Movie.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        AssertDetailOnlyFields(catalog.Movie, dto, k);
        Assert.Equal("movie", dto.Type);
        Assert.Equal(142, dto.DurationMinutes);
        Assert.Equal($"Movie Director {k}", dto.Director);
        Assert.True(dto.IsAnime);
        Assert.Equal($"Movie Studio {k}", dto.Studio);
        Assert.Equal($"Movie Romaji {k}", dto.RomajiTitle);
        Assert.Equal($"Notes {k}", dto.Notes);
    }

    [Fact]
    public async Task GetMediaDetail_Game_RoundTripsEveryField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Game.Title);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(catalog.Game.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        AssertDetailOnlyFields(catalog.Game, dto, k);
        Assert.Equal("game", dto.Type);
        Assert.Equal($"PC Platform {k}", dto.Platform);
        Assert.Equal(55, dto.HoursPlayed);
        Assert.Equal($"Game Developer {k}", dto.Studio);
    }

    [Fact]
    public async Task GetMediaDetail_Book_RoundTripsEveryField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Book.Title);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(catalog.Book.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        AssertDetailOnlyFields(catalog.Book, dto, k);
        Assert.Equal("book", dto.Type);
        Assert.Equal($"Book Author {k}", dto.Author);
        Assert.Equal(111, dto.CurrentPage);
        Assert.Equal(222, dto.TotalPages);
    }

    [Fact]
    public async Task GetMediaDetail_Manga_RoundTripsEveryFieldIncludingVolume()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Manga.Title);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(catalog.Manga.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        AssertDetailOnlyFields(catalog.Manga, dto, k);
        Assert.Equal("manga", dto.Type);
        Assert.Equal(5, dto.CurrentChapter);
        Assert.Equal(12, dto.TotalChapters);
        Assert.Equal($"Manga Author {k}", dto.Author);
        Assert.Equal($"Manga Romaji {k}", dto.RomajiTitle);
        Assert.Equal("manhwa", dto.MangaFormat);
        Assert.Equal(2, dto.CurrentVolume);
        Assert.Equal(4, dto.TotalVolumes);

        var volumeDto = Assert.Single(dto.Volumes!);
        var volume = catalog.MangaVolume;
        Assert.Equal(volume.Id, volumeDto.Id);
        Assert.Equal(2, volumeDto.VolumeNumber);
        Assert.Equal($"Volume Title {k}", volumeDto.Title);
        Assert.Equal($"/volumes/{k}.webp", volumeDto.CoverUrl);
        Assert.Equal(21, volumeDto.CurrentPage);
        Assert.Equal(42, volumeDto.TotalPages);
        Assert.Equal(5, volumeDto.CurrentChapter);
        Assert.Equal(9, volumeDto.TotalChapters);
        Assert.Equal(MediaStatus.InProgress, volumeDto.Status);
        Assert.Equal(6, volumeDto.Score);
        Assert.Equal($"Volume Notes {k}", volumeDto.Notes);
        Assert.Equal(T7, volumeDto.ReleaseDate);
        Assert.Equal(catalog.Manga.Id, volumeDto.MangaId);
    }

    [Fact]
    public async Task GetMediaDetail_TvShow_RoundTripsEveryFieldIncludingSeason()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.TvShow.Title);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(catalog.TvShow.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        AssertDetailOnlyFields(catalog.TvShow, dto, k);
        Assert.Equal("tvshow", dto.Type);
        Assert.Equal($"TvShow Network {k}", dto.Network);
        Assert.True(dto.IsAnime);
        Assert.Equal($"TvShow Studio {k}", dto.Studio);
        Assert.Equal($"TvShow Romaji {k}", dto.RomajiTitle);
        Assert.Equal(24, dto.DurationMinutes);
        Assert.Equal(12, dto.TotalEpisodesCount);
        Assert.Equal(4, dto.TotalEpisodesWatched);
        Assert.Equal(1, dto.SeasonsCount);

        var seasonDto = Assert.Single(dto.Seasons!);
        var season = catalog.TvSeason;
        Assert.Equal(season.Id, seasonDto.Id);
        Assert.Equal(1, seasonDto.SeasonNumber);
        Assert.Equal($"Season Title {k}", seasonDto.Title);
        Assert.Equal($"/seasons/{k}.webp", seasonDto.CoverUrl);
        Assert.Equal(4, seasonDto.CurrentEpisode);
        Assert.Equal(12, seasonDto.TotalEpisodes);
        Assert.Equal(MediaStatus.InProgress, seasonDto.Status);
        Assert.Equal(5, seasonDto.Score);
        Assert.Equal($"Season Notes {k}", seasonDto.Notes);
        Assert.Equal(T6, seasonDto.AirDate);
        Assert.Equal(season.EpisodesData, seasonDto.EpisodesData);
        Assert.Equal(catalog.TvShow.Id, seasonDto.TvShowId);
    }

    [Fact]
    public async Task GetMediaDetail_UnknownId_ReturnsNotFound()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new GetMediaDetailHandler(db);

        var result = await handler.HandleAsync(new GetMediaDetailQuery(Guid.NewGuid()), CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // GetMediaListHandler: фильтры + все поля MediaListDto
    // ------------------------------------------------------------------

    [Fact]
    public async Task GetMediaList_MovieProjection_RoundTripsEveryListField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Movie.Title);
        var handler = new GetMediaListHandler(db);

        var result = await handler.HandleAsync(
            new GetMediaListQuery(Type: "movie", Search: $"Movie Title {k}"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value);
        AssertBaseListFields(catalog.Movie, dto, k);
        Assert.Equal(142, dto.DurationMinutes);
        Assert.Equal($"Movie Director {k}", dto.Director);
        Assert.True(dto.IsAnime);
        Assert.Equal($"Movie Studio {k}", dto.Studio);
        Assert.Equal($"Movie Romaji {k}", dto.RomajiTitle);
    }

    [Fact]
    public async Task GetMediaList_TvShowProjection_RoundTripsEveryListField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.TvShow.Title);
        var handler = new GetMediaListHandler(db);

        var result = await handler.HandleAsync(
            new GetMediaListQuery(Type: "tvshow", Search: $"TvShow Title {k}"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value);
        AssertBaseListFields(catalog.TvShow, dto, k);
        Assert.Equal($"TvShow Network {k}", dto.Network);
        Assert.True(dto.IsAnime);
        Assert.Equal($"TvShow Studio {k}", dto.Studio);
        Assert.Equal($"TvShow Romaji {k}", dto.RomajiTitle);
        Assert.Equal(24, dto.DurationMinutes);
        Assert.Equal(12, dto.TotalEpisodesCount);
        Assert.Equal(4, dto.TotalEpisodesWatched);
        Assert.Equal(1, dto.SeasonsCount);
    }

    [Fact]
    public async Task GetMediaList_GameProjection_RoundTripsEveryListField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Game.Title);
        var handler = new GetMediaListHandler(db);

        var result = await handler.HandleAsync(
            new GetMediaListQuery(Type: "game", Search: $"Game Title {k}"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value);
        AssertBaseListFields(catalog.Game, dto, k);
        Assert.Equal($"PC Platform {k}", dto.Platform);
        Assert.Equal(55, dto.HoursPlayed);
        Assert.Equal($"Game Developer {k}", dto.Studio);
    }

    [Fact]
    public async Task GetMediaList_BookProjection_RoundTripsEveryListField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Book.Title);
        var handler = new GetMediaListHandler(db);

        var result = await handler.HandleAsync(
            new GetMediaListQuery(Type: "book", Search: $"Book Title {k}"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value);
        AssertBaseListFields(catalog.Book, dto, k);
        Assert.Equal($"Book Author {k}", dto.Author);
        Assert.Equal(111, dto.CurrentPage);
        Assert.Equal(222, dto.TotalPages);
    }

    [Fact]
    public async Task GetMediaList_MangaProjection_RoundTripsEveryListField()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Manga.Title);
        var handler = new GetMediaListHandler(db);

        var result = await handler.HandleAsync(
            new GetMediaListQuery(Type: "manga", Search: $"Manga Title {k}"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value);
        AssertBaseListFields(catalog.Manga, dto, k);
        Assert.Equal($"Manga Author {k}", dto.Author);
        Assert.Equal($"Manga Romaji {k}", dto.RomajiTitle);
        Assert.Equal("manhwa", dto.MangaFormat);
        Assert.Equal(5, dto.CurrentChapter);
        Assert.Equal(12, dto.TotalChapters);
        Assert.Equal(2, dto.CurrentVolume);
        Assert.Equal(4, dto.TotalVolumes);
    }

    [Fact]
    public async Task GetMediaList_TypeFilter_ReturnsOnlyRequestedType()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new GetMediaListHandler(db);

        var movies = await handler.HandleAsync(new GetMediaListQuery(Type: "movie"), CancellationToken.None);
        var games = await handler.HandleAsync(new GetMediaListQuery(Type: "game"), CancellationToken.None);
        var books = await handler.HandleAsync(new GetMediaListQuery(Type: "book"), CancellationToken.None);
        var manga = await handler.HandleAsync(new GetMediaListQuery(Type: "manga"), CancellationToken.None);
        var shows = await handler.HandleAsync(new GetMediaListQuery(Type: "tvshow"), CancellationToken.None);
        var unknown = await handler.HandleAsync(new GetMediaListQuery(Type: "nonsense"), CancellationToken.None);

        Assert.All(movies.Value, item => Assert.Equal("movie", item.Type));
        Assert.All(games.Value, item => Assert.Equal("game", item.Type));
        Assert.All(books.Value, item => Assert.Equal("book", item.Type));
        Assert.All(manga.Value, item => Assert.Equal("manga", item.Type));
        Assert.All(shows.Value, item => Assert.Equal("tvshow", item.Type));
        Assert.Empty(unknown.Value);
    }

    [Fact]
    public async Task GetMediaList_StatusAndAnimeFilters_Work()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new GetMediaListHandler(db);

        var inProgress = await handler.HandleAsync(
            new GetMediaListQuery(Status: MediaStatus.InProgress), CancellationToken.None);
        var anime = await handler.HandleAsync(new GetMediaListQuery(IsAnime: true), CancellationToken.None);
        var notAnime = await handler.HandleAsync(new GetMediaListQuery(IsAnime: false), CancellationToken.None);

        Assert.All(inProgress.Value, item => Assert.Equal(MediaStatus.InProgress, item.Status));
        Assert.All(anime.Value, item => Assert.True(item.IsAnime));
        Assert.All(notAnime.Value, item => Assert.False(item.IsAnime));
        Assert.Contains(anime.Value, item => item.Type == "movie");
        Assert.Contains(anime.Value, item => item.Type == "tvshow");
        Assert.Contains(notAnime.Value, item => item.Type == "movie");
    }

    [Fact]
    public async Task GetMediaList_SearchByFranchiseNameAndRomaji_Works()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Movie.Title);
        var handler = new GetMediaListHandler(db);

        var byFranchise = await handler.HandleAsync(
            new GetMediaListQuery(Search: $"Franchise Name {k}"), CancellationToken.None);
        var byRomaji = await handler.HandleAsync(
            new GetMediaListQuery(Search: $"Movie Romaji {k}"), CancellationToken.None);

        Assert.Contains(byFranchise.Value, item => item.Id == catalog.Movie.Id);
        Assert.Single(byRomaji.Value, item => item.Id == catalog.Movie.Id);
    }

    [Fact]
    public async Task GetMediaList_Sorting_Works()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new GetMediaListHandler(db);

        var byScoreAsc = await handler.HandleAsync(
            new GetMediaListQuery(SortBy: "score", SortOrder: "asc"), CancellationToken.None);
        var byScoreDesc = await handler.HandleAsync(
            new GetMediaListQuery(SortBy: "score", SortOrder: "desc"), CancellationToken.None);
        var byTitleAsc = await handler.HandleAsync(
            new GetMediaListQuery(SortBy: "title", SortOrder: "asc"), CancellationToken.None);
        Assert.True(byTitleAsc.IsSuccess);
        Assert.NotNull(byTitleAsc.Value);

        Assert.Equal(6, byScoreAsc.Value.Count);
        Assert.Equal(6, byScoreDesc.Value.Count);
        // Минимальный скор (манга, 6) — первый при asc и последний при desc; у live-action фильма
        // скор null, поэтому он в обоих направлениях в самом конце.
        Assert.Equal(6, byScoreAsc.Value.First().Score);
        // live-action фильм (score null) — в конце при desc
        Assert.Null(byScoreDesc.Value.Last().Score);
        Assert.Equal(
            byTitleAsc.Value.Select(i => i.Title).OrderBy(t => t, StringComparer.Ordinal),
            byTitleAsc.Value.Select(i => i.Title), StringComparer.Ordinal);
        Assert.Contains(byScoreAsc.Value, i => i.Id == catalog.Movie.Id);
    }

    // ------------------------------------------------------------------
    // CreateMediaHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task CreateMedia_Movie_PersistsEverySuppliedField()
    {
        using var db = CreateDbContext();
        var handler = CreateMediaHandler(db);

        var request = new CreateMediaRequest
        {
            Type = "movie",
            Title = "Created Movie",
            Status = MediaStatus.InProgress,
            Score = 7,
            Notes = "Created Notes",
            Description = "Created Description",
            TrailerVideoId = "created-trailer",
            FranchiseName = "Created Franchise",
            FranchiseOrder = 2,
            DurationMinutes = 96,
            Director = "Created Director",
            IsAnime = true,
            Studio = "Created Studio",
            RomajiTitle = "Created Romaji",
            ReleaseDate = T1,
            ReleaseYear = 2001,
            WatchedOn = "Created WatchedOn",
            EndDate = T2,
            ReleaseStatus = "Created ReleaseStatus",
            ExternalRating = 6.25,
            ExternalRatingVotes = 45,
            Genres = "Кибербезопасность, Астрофизика",
            Tags = "Created Tag One, Created Tag Two",
            UserPlatform = "Created UserPlatform",
        };

        var result = await handler.HandleAsync(new CreateMediaCommand(request), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;

        Assert.Equal("Created Movie", dto.Title);
        Assert.Equal("movie", dto.Type);
        Assert.Equal(MediaStatus.InProgress, dto.Status);
        Assert.Equal(7, dto.Score);
        Assert.Equal("Created Notes", dto.Notes);
        Assert.Equal("Created Description", dto.Description);
        Assert.Equal("created-trailer", dto.TrailerVideoId);
        Assert.Equal("Created Franchise", dto.FranchiseName);
        Assert.Equal(2, dto.FranchiseOrder);
        Assert.Equal(96, dto.DurationMinutes);
        Assert.Equal("Created Director", dto.Director);
        Assert.True(dto.IsAnime);
        Assert.Equal("Created Studio", dto.Studio);
        Assert.Equal("Created Romaji", dto.RomajiTitle);
        Assert.Equal(2001, dto.ReleaseYear);
        Assert.Equal("Created WatchedOn", dto.WatchedOn);
        Assert.Equal("Created ReleaseStatus", dto.ReleaseStatus);
        Assert.Equal(6.25, dto.ExternalRating);
        Assert.Equal(45, dto.ExternalRatingVotes);
        Assert.Equal(new[] { "Кибербезопасность", "Астрофизика" }, dto.Genres);
        Assert.Equal("Created Tag One, Created Tag Two", dto.Tags);
        Assert.Equal("Created UserPlatform", dto.UserPlatform);
        Assert.Equal(SyncStatus.Ready, dto.SyncStatus);
        Assert.NotNull(dto.LastActivityAt);

        var stored = await db.Movies.SingleAsync(m => m.Title == "Created Movie");
        Assert.Equal(dto.Id, stored.Id);
        Assert.Equal("Created Franchise", (await db.Franchises.SingleAsync()).Name);
        var events = await db.Events.ToListAsync();
        Assert.Single(events, e => e.MediaId == stored.Id && e.Type == MediaEventType.Added);
    }

    [Fact]
    public async Task CreateMedia_TvShow_SeasonsAreSeeded()
    {
        using var db = CreateDbContext();
        var handler = CreateMediaHandler(db);

        var request = new CreateMediaRequest
        {
            Type = "tvshow",
            Title = "Created Show",
            Network = "Created Network",
            EpisodeDurationMinutes = 45,
            Seasons = [new CreateSeasonRequest { SeasonNumber = 1, Title = "S1", TotalEpisodes = 8 }],
        };

        var result = await handler.HandleAsync(new CreateMediaCommand(request), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var stored = await db.TvShows.Include(s => s.Seasons).SingleAsync(s => s.Title == "Created Show");
        var season = Assert.Single(stored.Seasons);
        Assert.Equal(8, season.TotalEpisodes);
        Assert.Equal(45, stored.EpisodeDurationMinutes);
    }

    [Fact]
    public async Task CreateMedia_ExternalId_DefersEnrichmentAndSetsSyncing()
    {
        using var db = CreateDbContext();
        var jobs = new StubJobManager();
        var handler = CreateMediaHandler(db, jobs: jobs);

        var request = new CreateMediaRequest
        {
            Type = "game",
            Title = "Created From Search",
            Platform = "PC",
            ExternalId = "ext-123",
            ExternalSource = "rawg",
        };

        var result = await handler.HandleAsync(new CreateMediaCommand(request), CancellationToken.None);

        Assert.True(result.IsSuccess);
        Assert.Equal(SyncStatus.Syncing, result.Value.SyncStatus);
        Assert.Equal(1, jobs.EnqueuedCount);
    }

    [Fact]
    public async Task CreateMedia_InvalidRequest_ReturnsValidationError()
    {
        using var db = CreateDbContext();
        var handler = CreateMediaHandler(db);

        var result = await handler.HandleAsync(
            new CreateMediaCommand(new CreateMediaRequest { Type = "movie", Title = "" }),
            CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    private static CreateMediaHandler CreateMediaHandler(AppDbContext db, StubJobManager? jobs = null)
    {
        var validator = new CreateMediaRequestValidator();
        var franchiseService = new FranchiseService();
        return new CreateMediaHandler(
            db,
            validator,
            new StubImageStorage(),
            franchiseService,
            jobs ?? new StubJobManager(),
            new MemoryCache(new MemoryCacheOptions()));
    }

    // ------------------------------------------------------------------
    // UpdateMediaHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task UpdateMedia_Movie_PersistsEveryChangedFieldAndRecordsEvents()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Movie.Title);
        var handler = new UpdateMediaHandler(
            db,
            new UpdateMediaRequestValidator(),
            new FranchiseService(),
            new MemoryCache(new MemoryCacheOptions()));

        var request = new UpdateMediaRequest
        {
            Title = "Updated Movie Title",
            Score = 9,
            Status = MediaStatus.Completed,
            Notes = "Updated Notes",
            DetailedScoreJson = Serialize(new[] { new { Key = "updated", Value = 9 } }),
            QuotesJson = Serialize(new[] { new { Quote = "Updated Quote" } }),
            StartedAt = T6,
            FinishedAt = T7,
            LastActivityAt = T8,
            Genres = "Кибербезопасность",
            Tags = "Updated Tag",
            UnlockedAchievements = "Updated Achievement",
            UserPlatform = "Updated UserPlatform",
            WatchedOn = "Updated WatchedOn",
            TranslatedSynopsis = "Updated Synopsis",
            TranslationLanguage = "ru",
            RelatedMediaJson = Serialize(new[] { new ExternalMediaDto { ExternalId = "rel-1", Title = "Related 1", Type = "movie" } }),
            RelatedSource = "tmdb",
            RecommendationsJson = Serialize(new[] { new ExternalRecommendationDto("rec-1", "Rec 1", null, 8.0, "tmdb") }),
            AchievementsJson = Serialize(new[] { new { Name = "Updated Achievement Json", Percent = 90 } }),
            FranchiseName = "Updated Franchise",
        };

        var result = await handler.HandleAsync(new UpdateMediaCommand(catalog.Movie.Id, request), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = result.Value;
        Assert.Equal("Updated Movie Title", dto.Title);
        Assert.Equal(9, dto.Score);
        Assert.Equal(MediaStatus.Completed, dto.Status);
        Assert.Equal("Updated Notes", dto.Notes);
        Assert.Equal(request.DetailedScoreJson, dto.DetailedScoreJson);
        Assert.Equal(request.QuotesJson, dto.QuotesJson);
        Assert.Equal(T6, dto.StartedAt);
        Assert.Equal(T7, dto.FinishedAt);
        Assert.Equal(T8, dto.LastActivityAt);
        Assert.Equal(new[] { "Кибербезопасность" }, dto.Genres);
        Assert.Equal("Updated Tag", dto.Tags);
        Assert.Equal("Updated Achievement", dto.UnlockedAchievements);
        Assert.Equal("Updated UserPlatform", dto.UserPlatform);
        Assert.Equal("Updated WatchedOn", dto.WatchedOn);
        Assert.Equal("Updated Synopsis", dto.TranslatedSynopsis);
        Assert.Equal("ru", dto.TranslationLanguage);
        // RomajiTitle в MediaItemUpdater применяется только к манге: у фильма значение
        // остаётся тем, что записал сид, — это фиксирует текущее поведение обновления.
        Assert.Equal($"Movie Romaji {k}", dto.RomajiTitle);
        Assert.Equal(request.RelatedMediaJson, dto.RelatedMediaJson);
        Assert.Equal("tmdb", dto.RelatedSource);
        Assert.Equal(request.RecommendationsJson, dto.RecommendationsJson);
        Assert.Equal(request.AchievementsJson, dto.AchievementsJson);
        Assert.Equal("Updated Franchise", dto.FranchiseName);
        Assert.True(dto.IsCustomEdited);

        var stored = await db.Movies.SingleAsync(m => m.Id == catalog.Movie.Id);
        Assert.Equal(MediaStatus.Completed, stored.Status);
        Assert.True(stored.IsCustomEdited);

        var events = await db.Events.Where(e => e.MediaId == catalog.Movie.Id).ToListAsync();
        Assert.Contains(events, e => e.Type == MediaEventType.StatusChanged);
        Assert.Contains(events, e => e.Type == MediaEventType.ScoreChanged);
    }

    [Fact]
    public async Task UpdateMedia_ClearFlags_ClearWatchedOnAndDropReason()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateMediaHandler(
            db,
            new UpdateMediaRequestValidator(),
            new FranchiseService(),
            new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(new UpdateMediaCommand(catalog.Movie.Id, new UpdateMediaRequest
        {
            ClearWatchedOn = true,
            ClearDropReason = true,
            ClearScore = true,
        }), CancellationToken.None);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Value.WatchedOn);
        Assert.Null(result.Value.DropReason);
        Assert.Null(result.Value.Score);
    }

    [Fact]
    public async Task UpdateMedia_UnknownId_ReturnsNotFound()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new UpdateMediaHandler(
            db,
            new UpdateMediaRequestValidator(),
            new FranchiseService(),
            new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateMediaCommand(Guid.NewGuid(), new UpdateMediaRequest { Title = "Nope" }),
            CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // UpdateProgressHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task UpdateProgress_Book_ClampsAndRecordsEvent()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateProgressHandler(db, new UpdateProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateProgressCommand(catalog.Book.Id, 300), CancellationToken.None);

        Assert.True(result.IsSuccess);
        // ExecuteUpdateAsync пишет мимо change tracker, поэтому перечитываем без трекинга.
        var book = await db.Books.AsNoTracking().SingleAsync(b => b.Id == catalog.Book.Id);
        Assert.Equal(222, book.CurrentPage);
        var progressEvent = Assert.Single(
            await db.Events.Where(e => e.MediaId == catalog.Book.Id && e.Type == MediaEventType.ProgressChanged).ToListAsync());
        Assert.Equal("111 стр.", progressEvent.OldValue);
        Assert.Equal("222 стр.", progressEvent.NewValue);
    }

    [Fact]
    public async Task UpdateProgress_Manga_ClampsToTotalChapters()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateProgressHandler(db, new UpdateProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateProgressCommand(catalog.Manga.Id, 100), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var manga = await db.Manga.AsNoTracking().SingleAsync(m => m.Id == catalog.Manga.Id);
        Assert.Equal(12, manga.CurrentChapter);
        var progressEvent = Assert.Single(
            await db.Events.Where(e => e.MediaId == catalog.Manga.Id && e.Type == MediaEventType.ProgressChanged).ToListAsync());
        Assert.Equal("5 гл.", progressEvent.OldValue);
        Assert.Equal("12 гл.", progressEvent.NewValue);
    }

    [Fact]
    public async Task UpdateProgress_Game_RecordsHours()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateProgressHandler(db, new UpdateProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateProgressCommand(catalog.Game.Id, 70), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var game = await db.Games.AsNoTracking().SingleAsync(g => g.Id == catalog.Game.Id);
        Assert.Equal(70, game.HoursPlayed);
        var progressEvent = Assert.Single(
            await db.Events.Where(e => e.MediaId == catalog.Game.Id && e.Type == MediaEventType.ProgressChanged).ToListAsync());
        Assert.Equal("55 ч.", progressEvent.OldValue);
        Assert.Equal("70 ч.", progressEvent.NewValue);
    }

    [Fact]
    public async Task UpdateProgress_Movie_ReturnsUnsupported()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateProgressHandler(db, new UpdateProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateProgressCommand(catalog.Movie.Id, 10), CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // UpdateSeasonProgressHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task UpdateSeasonProgress_CompletesSeasonAndShow()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateSeasonProgressHandler(db, new UpdateSeasonProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateSeasonProgressCommand(catalog.TvSeason.Id, 12), CancellationToken.None);

        Assert.True(result.IsSuccess);
        // ExecuteUpdateAsync пишет мимо change tracker, поэтому перечитываем без трекинга.
        var season = await db.TvSeasons.AsNoTracking().SingleAsync(s => s.Id == catalog.TvSeason.Id);
        Assert.Equal(12, season.CurrentEpisode);
        Assert.Equal(MediaStatus.Completed, season.Status);

        var show = await db.TvShows.AsNoTracking().SingleAsync(s => s.Id == catalog.TvShow.Id);
        Assert.Equal(MediaStatus.Completed, show.Status);
        Assert.NotNull(show.FinishedAt);

        var progressEvent = Assert.Single(
            await db.Events.Where(e => e.MediaId == catalog.TvShow.Id && e.Type == MediaEventType.ProgressChanged).ToListAsync());
        Assert.Equal("S1 E4", progressEvent.OldValue);
        Assert.Equal("S1 E12", progressEvent.NewValue);
    }

    [Fact]
    public async Task UpdateSeasonProgress_MidSeason_KeepsShowInProgress()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateSeasonProgressHandler(db, new UpdateSeasonProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateSeasonProgressCommand(catalog.TvSeason.Id, 7), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var season = await db.TvSeasons.AsNoTracking().SingleAsync(s => s.Id == catalog.TvSeason.Id);
        Assert.Equal(7, season.CurrentEpisode);
        Assert.Equal(MediaStatus.InProgress, season.Status);
        Assert.Equal(MediaStatus.InProgress, (await db.TvShows.AsNoTracking().SingleAsync(s => s.Id == catalog.TvShow.Id)).Status);
    }

    [Fact]
    public async Task UpdateSeasonProgress_UnknownSeason_ReturnsNotFound()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new UpdateSeasonProgressHandler(db, new UpdateSeasonProgressRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateSeasonProgressCommand(Guid.NewGuid(), 1), CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // UpdateStatusHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task UpdateStatus_Drop_KeepsReasonAndNotesAndRecordsEvent()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateStatusHandler(db, new UpdateStatusRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateStatusCommand(catalog.Movie.Id, MediaStatus.Dropped, "Dropped: boring", "Dropped: notes"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var movie = await db.Movies.SingleAsync(m => m.Id == catalog.Movie.Id);
        Assert.Equal(MediaStatus.Dropped, movie.Status);
        Assert.Equal("Dropped: boring", movie.DropReason);
        Assert.Equal("Dropped: notes", movie.DropNotes);
        Assert.NotNull(movie.FinishedAt);
        Assert.NotNull(movie.LastActivityAt);

        var statusEvent = Assert.Single(
            await db.Events.ToListAsync(),
            e => e.Id != catalog.MediaEvent.Id
                && e.MediaId == catalog.Movie.Id
                && e.Type == MediaEventType.StatusChanged);
        Assert.Equal(MediaStatus.InProgress.ToString(), statusEvent.OldValue);
        Assert.Equal(MediaStatus.Dropped.ToString(), statusEvent.NewValue);
    }

    [Fact]
    public async Task UpdateStatus_Complete_SetsFinishedAt()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new UpdateStatusHandler(db, new UpdateStatusRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateStatusCommand(catalog.Game.Id, MediaStatus.Completed), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var game = await db.Games.AsNoTracking().SingleAsync(g => g.Id == catalog.Game.Id);
        Assert.Equal(MediaStatus.Completed, game.Status);
        Assert.NotNull(game.FinishedAt);
    }

    [Fact]
    public async Task UpdateStatus_UnknownId_ReturnsNotFound()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new UpdateStatusHandler(db, new UpdateStatusRequestValidator(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(
            new UpdateStatusCommand(Guid.NewGuid(), MediaStatus.Planned), CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // DeleteMediaHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task DeleteMedia_RemovesRowAndCascade()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var handler = new DeleteMediaHandler(db, new StubImageStorage(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(new DeleteMediaCommand(catalog.Movie.Id), CancellationToken.None);

        Assert.True(result.IsSuccess);
        Assert.False(await db.Movies.AnyAsync(m => m.Id == catalog.Movie.Id));
        Assert.False(await db.Events.AnyAsync(e => e.MediaId == catalog.Movie.Id));
    }

    [Fact]
    public async Task DeleteMedia_UnknownId_ReturnsNotFound()
    {
        using var db = CreateDbContext();
        await SeedFullCatalogAsync(db);
        var handler = new DeleteMediaHandler(db, new StubImageStorage(), new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(new DeleteMediaCommand(Guid.NewGuid()), CancellationToken.None);

        Assert.False(result.IsSuccess);
    }

    // ------------------------------------------------------------------
    // GetMediaStatsHandler
    // ------------------------------------------------------------------

    private static async Task<AppDbContext> SeedStatsCatalogAsync(AppDbContext db)
    {
        var k = Suffix("stats");

        var completedGame = new VideoGame { Title = $"Stats Game {k}", Platform = "PC", HoursPlayed = 10 };
        var completedBook = new Book { Title = $"Stats Book {k}", Author = "A", TotalPages = 200, CurrentPage = 200 };
        var completedMovie = new Movie { Title = $"Stats Movie {k}" };
        var inProgressManga = new Manga { Title = $"Stats Manga {k}", Author = "M", CurrentChapter = 7, TotalChapters = 20 };
        var plannedBook = new Book { Title = $"Stats Planned Book {k}", Author = "B" };

        var season = new TvSeason { Id = Guid.NewGuid(), SeasonNumber = 1, Title = "Season 1", TotalEpisodes = 12, CurrentEpisode = 5 };
        var inProgressShow = new TvShow { Title = $"Stats Show {k}", EpisodeDurationMinutes = 45 };
        inProgressShow.Seasons.Add(season);
        season.TvShow = inProgressShow;
        season.TvShowId = inProgressShow.Id;

        completedGame.ChangeStatus(MediaStatus.Completed);
        completedBook.ChangeStatus(MediaStatus.Completed);
        completedMovie.ChangeStatus(MediaStatus.Completed);
        inProgressManga.SetChapter(7);
        plannedBook.ChangeStatus(MediaStatus.Planned);
        inProgressShow.SetEpisodeProgressAndSync();

        db.MediaItems.Add(completedGame);
        db.MediaItems.Add(completedBook);
        db.MediaItems.Add(completedMovie);
        db.MediaItems.Add(inProgressManga);
        db.MediaItems.Add(plannedBook);
        db.MediaItems.Add(inProgressShow);
        db.TvSeasons.Add(season);
        await db.SaveChangesAsync();
        return db;
    }

    [Fact]
    public async Task GetMediaStats_HandleAsync_CountsEverything()
    {
        using var db = await SeedStatsCatalogAsync(CreateDbContext());
        var handler = new GetMediaStatsHandler(db, new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAsync(CancellationToken.None);

        Assert.True(result.IsSuccess);
        var stats = result.Value;
        Assert.Equal(6, stats.TotalItems);
        Assert.Equal(3, stats.CompletedItems);
        Assert.Equal(2, stats.InProgressItems);
        Assert.Equal(1, stats.PlannedItems);
        Assert.Equal(1, stats.CompletedGamesCount);
        Assert.Equal(1, stats.CompletedBooksCount);
        Assert.Equal(1, stats.CompletedMoviesCount);
        Assert.Equal(10, stats.TotalHoursPlayed);
        Assert.Equal(200, stats.TotalPagesRead);
        Assert.Equal(7, stats.TotalChaptersRead);
        Assert.Equal(5, stats.TotalEpisodesWatched);
    }

    [Fact]
    public async Task GetMediaStats_HandleAdvancedAsync_SumsProgressAndScores()
    {
        using var db = await SeedStatsCatalogAsync(CreateDbContext());
        var handler = new GetMediaStatsHandler(db, new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleAdvancedAsync("all", CancellationToken.None);

        Assert.True(result.IsSuccess);
        var stats = result.Value;
        Assert.Equal(6, stats.TotalTitles);
        Assert.Equal(3, stats.CompletedTitles);
        Assert.Equal(10, stats.GameHours);
        Assert.Equal(200, stats.TotalPagesRead);
        Assert.Equal(7, stats.TotalChaptersRead);
        Assert.Equal(5, stats.TotalEpisodesWatched);
        Assert.Equal(5, stats.SeriesEpisodesWatched);
    }

    [Fact]
    public async Task GetMediaStats_HandleTasteProfileAsync_ReturnsProfile()
    {
        using var db = await SeedStatsCatalogAsync(CreateDbContext());
        var handler = new GetMediaStatsHandler(db, new MemoryCache(new MemoryCacheOptions()));

        var result = await handler.HandleTasteProfileAsync("all", CancellationToken.None);

        Assert.True(result.IsSuccess);
        var profile = result.Value;
        Assert.NotNull(profile.Persona);
        Assert.NotEmpty(profile.Persona.Title);
        Assert.NotNull(profile.SunkCost);
        Assert.NotNull(profile.Divergence);
        Assert.NotNull(profile.DropAnalytics);
        Assert.Equal(0, profile.DropAnalytics.TotalDropped);
    }

    // ------------------------------------------------------------------
    // ListsService
    // ------------------------------------------------------------------

    [Fact]
    public async Task ListsService_GetListsAsync_SummaryPreservesListFields()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Game.Title);
        var service = new ListsService(db);

        var lists = await service.GetListsAsync(CancellationToken.None);

        var summary = Assert.Single(lists);
        Assert.Equal(catalog.CustomList.Id, summary.Id);
        Assert.Equal($"List Name {k}", summary.Name);
        Assert.Equal($"List Description {k}", summary.Description);
        Assert.Equal("star", summary.Icon);
        Assert.Equal("#A1B2C3", summary.Color);
        Assert.Equal(1, summary.ItemsCount);
        Assert.Equal(T4, summary.UpdatedAt);
        Assert.False(summary.IsSmart);
        Assert.Null(summary.SmartQueryJson);
        Assert.Equal(catalog.Game.CoverUrl, Assert.Single(summary.PreviewCovers));
    }

    [Fact]
    public async Task ListsService_GetListDetailAsync_PreservesListAndItemMediaFields()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Game.Title);
        var service = new ListsService(db);

        var detail = await service.GetListDetailAsync(catalog.CustomList.Id, CancellationToken.None);

        Assert.NotNull(detail);
        Assert.Equal($"List Name {k}", detail.Name);
        Assert.Equal(T5, detail.CreatedAt);
        Assert.Equal(T4, detail.UpdatedAt);
        var item = Assert.Single(detail.Items);
        Assert.Equal(catalog.Game.Id, item.Id);
        Assert.Equal("game", item.Type);
        Assert.Equal($"Game Title {k}", item.Title);
        Assert.Equal($"Game Developer {k}", item.Studio);
        Assert.Equal(55, item.HoursPlayed);
    }

    [Fact]
    public async Task ListsService_CreateUpdateDeleteAddRemove_Work()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var service = new ListsService(db);

        var listId = await service.CreateAsync(
            new CreateListRequest("Created List", "Desc", "heart", "#FFFFFF", null), CancellationToken.None);
        Assert.NotEqual(Guid.Empty, listId);

        var updated = await service.UpdateAsync(
            listId, new UpdateListRequest("Updated List", null, "star", "#000000", null), CancellationToken.None);
        Assert.True(updated);
        var stored = await db.CustomLists.SingleAsync(l => l.Id == listId);
        Assert.Equal("Updated List", stored.Name);
        Assert.Equal("star", stored.Icon);
        Assert.Equal("#000000", stored.Color);

        Assert.True(await service.AddMediaAsync(listId, catalog.Game.Id, CancellationToken.None));
        var listIds = await service.GetListsForMediaAsync(catalog.Game.Id, CancellationToken.None);
        Assert.Contains(listId, listIds);
        var summary = Assert.Single(await service.GetListsAsync(CancellationToken.None), l => l.Id == listId);
        Assert.Equal(1, summary.ItemsCount);

        Assert.True(await service.RemoveMediaAsync(listId, catalog.Game.Id, CancellationToken.None));
        Assert.Equal(0, (await service.GetListsAsync(CancellationToken.None)).Single(l => l.Id == listId).ItemsCount);

        Assert.True(await service.DeleteAsync(listId, CancellationToken.None));
        Assert.False(await db.CustomLists.AnyAsync(l => l.Id == listId));
    }

    // ------------------------------------------------------------------
    // GetHistoryEventsHandler
    // ------------------------------------------------------------------

    [Fact]
    public async Task GetHistoryEvents_PreservesEveryFieldAndJoinsTitle()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var k = ExtractKey(catalog.Movie.Title);
        var handler = new GetHistoryEventsHandler(db);

        var result = await handler.HandleAsync(new GetHistoryEventsQuery(), CancellationToken.None);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Value, e => e.Id == catalog.MediaEvent.Id);
        Assert.Equal(catalog.MediaEvent.Id, dto.Id);
        Assert.Equal(catalog.Movie.Id, dto.MediaId);
        Assert.Equal("StatusChanged", dto.Type);
        Assert.Equal($"Event Old {k}", dto.OldValue);
        Assert.Equal($"Event New {k}", dto.NewValue);
        Assert.Equal(T9, dto.CreatedAt);
        Assert.Equal($"Movie Title {k}", dto.Title);
    }

    [Fact]
    public async Task GetHistoryEvents_FiltersByMediaAndDate()
    {
        using var db = CreateDbContext();
        var catalog = await SeedFullCatalogAsync(db);
        var otherEvent = new MediaEvent
        {
            Id = Guid.NewGuid(),
            MediaId = catalog.Game.Id,
            Media = catalog.Game,
            Type = MediaEventType.ScoreChanged,
            OldValue = "9",
            NewValue = "5",
            CreatedAt = T12,
        };
        db.Events.Add(otherEvent);
        await db.SaveChangesAsync();
        var handler = new GetHistoryEventsHandler(db);

        var byMedia = await handler.HandleAsync(
            new GetHistoryEventsQuery(MediaId: catalog.Game.Id), CancellationToken.None);
        var single = Assert.Single(byMedia.Value);
        Assert.Equal(otherEvent.Id, single.Id);
        Assert.Equal($"Game Title {ExtractKey(catalog.Game.Title)}", single.Title);

        var byDate = await handler.HandleAsync(
            new GetHistoryEventsQuery(Date: DateOnly.FromDateTime(T12)), CancellationToken.None);
        Assert.Single(byDate.Value, e => e.Id == otherEvent.Id);
    }

    // ------------------------------------------------------------------
    // Вспомогательное
    // ------------------------------------------------------------------

    /// <summary>Суффикс вида "f_{guid}", который SeedFullCatalogAsync подставляет в каждое поле.</summary>
    private static string ExtractKey(string title) => title[(title.LastIndexOf(' ') + 1)..];

    private sealed class StubImageStorage : IImageStorageService
    {
        public Task<string?> SaveCoverAsync(
            string externalUrl, Guid itemId, CancellationToken ct = default, string folder = "cover") =>
            Task.FromResult<string?>($"/covers/{itemId}.webp");

        public Task<MediaCoverItemDto?> SaveCoverVariantAsync(
            string externalUrl, Guid itemId, string? source = null, CancellationToken ct = default) =>
            Task.FromResult<MediaCoverItemDto?>(new MediaCoverItemDto(
                "v1",
                $"/media-assets/{itemId}/covers/v1/thumb.webp",
                $"/media-assets/{itemId}/covers/v1/original.webp",
                source,
                DateTime.UtcNow));

        public Task<MediaCoverItemDto?> SaveCoverVariantAsync(
            Stream content, Guid itemId, string? source = null, CancellationToken ct = default) =>
            Task.FromResult<MediaCoverItemDto?>(new MediaCoverItemDto(
                "v1",
                $"/media-assets/{itemId}/covers/v1/thumb.webp",
                $"/media-assets/{itemId}/covers/v1/original.webp",
                source,
                DateTime.UtcNow));

        public void DeleteCoverVariant(Guid itemId, string coverId)
        {
        }

        public void DeleteCover(string? localCoverUrl)
        {
        }

        public void DeleteMediaFolder(Guid mediaId)
        {
        }
    }

    private sealed class StubJobManager : IJobManager
    {
        public int EnqueuedCount { get; private set; }

        public Guid Enqueue(
            Guid? mediaId, string title,
            Func<IServiceProvider, CancellationToken, IProgress<JobProgressDto>, Task> work)
        {
            EnqueuedCount++;
            return Guid.NewGuid();
        }

        public IReadOnlyList<JobProgressDto> GetSnapshot() => [];

        public bool CancelJob(Guid jobId) => false;

        public IAsyncEnumerable<JobProgressDto> SubscribeAsync(CancellationToken ct)
        {
            return EmptyAsync();

            static async IAsyncEnumerable<JobProgressDto> EmptyAsync()
            {
                await Task.CompletedTask;
                yield break;
            }
        }

        public ChannelReader<QueuedJob> Reader => Channel.CreateUnbounded<QueuedJob>().Reader;

        public CancellationTokenSource CreateRunnerToken(Guid jobId, CancellationToken stoppingToken) =>
            CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
    }
}

/// <summary>Хэндлер-хелпер: выставляет эпизоды сезона и синхронизирует статус шоу.</summary>
file static class DatabaseFieldPreservationTestExtensions
{
    public static void SetEpisodeProgressAndSync(this TvShow show)
    {
        foreach (var season in show.Seasons)
        {
            season.SetEpisode(season.CurrentEpisode);
        }

        show.SyncStatusFromSeasons();
    }
}
