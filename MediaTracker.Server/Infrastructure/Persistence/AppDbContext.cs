using System.Collections;
using System.Collections.Concurrent;
using System.Data.Common;
using System.Linq.Expressions;
using Dapper;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using Microsoft.Data.Sqlite;
using System.Reflection;

namespace MediaTracker.Server.Infrastructure.Persistence;

public sealed class AppDbContext : IDisposable, IAsyncDisposable
{
    static AppDbContext()
    {
        // Ensure Dapper type handlers (Guid as TEXT, DateTime as ISO 8601) are registered
        // before any Dapper call executes. Required because Dapper.AOT generates its own
        // deserializers that bypass the default SqlMapper type resolution.
        DapperConfiguration.EnsureInitialized();
    }

    public AppDbContext(string connectionString)
    {
        _connection = new SqliteConnection(connectionString);
    }

    private readonly SqliteConnection _connection;

    public SqliteConnection Connection => _connection;

    public void Dispose()
    {
        _connection.Dispose();
    }

    public ValueTask DisposeAsync()
    {
        return _connection.DisposeAsync();
    }

    // ------------------------------------------------------------------
    // EF Core compatibility shim for tests
    // ------------------------------------------------------------------

    private readonly List<object> _pendingAdds = new();
    private readonly List<object> _pendingRemoves = new();
    private readonly List<MediaItem> _trackedMediaItems = new();
    private bool _foreignKeysSuspended;

    /// <summary>Adds an entity to the pending insert queue.</summary>
    public void Add(object entity) => _pendingAdds.Add(entity);

    /// <summary>Adds multiple entities to the pending insert queue.</summary>
    public void AddRange(params object[] entities)
    {
        foreach (var e in entities) _pendingAdds.Add(e);
    }

    /// <summary>Adds multiple entities to the pending insert queue.</summary>
    public void AddRange(IEnumerable<object> entities)
    {
        foreach (var e in entities) _pendingAdds.Add(e);
    }

    /// <summary>Database facade for EF Core compatibility in tests.</summary>
    public DatabaseFacadeShim Database => new(this);

    /// <summary>Flushes all pending adds and removes to the database via Dapper.</summary>
    public async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        // EF Core / Microsoft.Data.Sqlite never enforced foreign keys on this code path, so test
        // seeds may insert children before their parents. Suspend FK checks for this context from
        // the first SaveChanges on; cascade deletes are handled explicitly in DeleteMediaItemAsync.
        _foreignKeysSuspended = true;

        // EF infers foreign keys from navigation properties at DetectChanges time; the shim must
        // do the same so seeds can set item.Franchise / season.TvShow / volume.Manga without ids.
        var franchisesToEnsure = new List<Franchise>();
        foreach (var entity in _pendingAdds)
        {
            switch (entity)
            {
                case MediaItem mi when mi.Franchise is { } franchise:
                    mi.FranchiseId = franchise.Id;
                    if (!_pendingAdds.Any(e => ReferenceEquals(e, franchise)) && !franchisesToEnsure.Contains(franchise))
                    {
                        franchisesToEnsure.Add(franchise);
                    }
                    break;
                case TvSeason season when season.TvShow is { } show:
                    season.TvShowId = show.Id;
                    break;
                case MangaVolume volume when volume.Manga is { } manga:
                    volume.MangaId = manga.Id;
                    break;
                case MediaEvent evt when evt.Media is { } media:
                    evt.MediaId = media.Id;
                    break;
                case CustomListItem cli when cli.List is { } list:
                    cli.ListId = list.Id;
                    break;
            }
        }

        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        // Nested franchise graphs (item.Franchise = new Franchise {...}) are inserted by EF automatically.
        foreach (var franchise in franchisesToEnsure)
        {
            await CreateFranchiseAsync(franchise, ct);
        }

        // EF change tracking persists mutations to previously saved entities on the next SaveChanges;
        // the shim replays tracked media items as full updates.
        foreach (var tracked in _trackedMediaItems)
        {
            await UpdateMediaItemAsync(tracked, ct);
        }

        int count = 0;
        foreach (var entity in _pendingAdds)
        {
            await InsertEntityAsync(entity, ct);
            count++;
        }
        foreach (var entity in _pendingRemoves)
        {
            await RemoveEntityAsync(entity, ct);
            count++;
        }

        _pendingAdds.Clear();
        _pendingRemoves.Clear();
        return count;
    }

    private async Task InsertEntityAsync(object entity, CancellationToken ct)
    {
        switch (entity)
        {
            case MediaItem mi:
                await InsertMediaItemAsync(mi, ct);
                if (!_trackedMediaItems.Any(t => ReferenceEquals(t, mi)))
                {
                    _trackedMediaItems.Add(mi);
                }
                // EF cascade-inserts seasons/volumes attached to the parent's navigation collection.
                if (mi is TvShow show)
                {
                    foreach (var season in show.Seasons)
                    {
                        season.TvShowId = show.Id;
                        await InsertTvSeasonAsync(season, ct);
                    }
                }
                if (mi is Manga manga)
                {
                    foreach (var volume in manga.Volumes)
                    {
                        volume.MangaId = manga.Id;
                        await InsertMangaVolumeAsync(volume, ct);
                    }
                }
                return;
            case MangaVolume mv: await InsertMangaVolumeAsync(mv, ct); return;
            case TvSeason ts: await InsertTvSeasonAsync(ts, ct); return;
            case Franchise f: await CreateFranchiseAsync(f, ct); return;
            case CustomList cl:
                await CreateCustomListAsync(cl, ct);
                foreach (var cli in cl.Items) await InsertCustomListItemAsync(cli, ct);
                return;
            case CustomListItem cli: await AddCustomListItemAsync(cli.ListId, cli.MediaItemId, ct); return;
            case MediaEvent me: await InsertMediaEventAsync(me, ct); return;
            case AppSetting s: await SetSettingAsync(s.Key, s.Value, ct); return;
            case ApiToken at: await CreateApiTokenAsync(at, ct); return;
        }
    }

    private async Task RemoveEntityAsync(object entity, CancellationToken ct)
    {
        switch (entity)
        {
            case MediaItem mi:
                _trackedMediaItems.RemoveAll(t => ReferenceEquals(t, mi));
                await DeleteMediaItemAsync(mi.Id, ct);
                return;
            case MangaVolume mv: /* no delete method yet; skip */ return;
            case TvSeason ts: /* no delete method yet; skip */ return;
            case Franchise f: /* no delete method yet; skip */ return;
            case CustomList cl: await DeleteCustomListAsync(cl.Id, ct); return;
            case CustomListItem cli: await RemoveCustomListItemAsync(cli.ListId, cli.MediaItemId, ct); return;
            case MediaEvent me: await DeleteMediaEventAsync(me.Id, ct); return;
            case AppSetting s: await DeleteSettingAsync(s.Key, ct); return;
            case ApiToken at: await DeleteApiTokenAsync(at.Id, ct); return;
        }
    }

    // ------------------------------------------------------------------
    // DbSet shims for EF Core compatibility in tests
    // ------------------------------------------------------------------

    public DbSetShim<MediaItem> MediaItems => new(this, async (ct) =>
        (await LoadMediaItemsAsync(null, null, null, null, null, null, ct)).ToList());
    public DbSetShim<VideoGame> Games => new(this, async (ct) =>
        (await LoadMediaItemsAsync("Game", null, null, null, null, null, ct)).OfType<VideoGame>().ToList());
    public DbSetShim<Book> Books => new(this, async (ct) =>
        (await LoadMediaItemsAsync("Book", null, null, null, null, null, ct)).OfType<Book>().ToList());
    public DbSetShim<Manga> Manga => new(this, async (ct) =>
        (await LoadMediaItemsAsync("Manga", null, null, null, null, null, ct)).OfType<Manga>().ToList());
    public DbSetShim<Movie> Movies => new(this, async (ct) =>
        (await LoadMediaItemsAsync("Movie", null, null, null, null, null, ct)).OfType<Movie>().ToList());
    public DbSetShim<TvShow> TvShows => new(this, async (ct) =>
        (await LoadMediaItemsAsync("TvShow", null, null, null, null, null, ct)).OfType<TvShow>().ToList());
    public DbSetShim<TvSeason> TvSeasons => new(this, async (ct) =>
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM TvSeasons;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<TvSeason>();
        while (await reader.ReadAsync(ct))
            list.Add(new TvSeason
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                SeasonNumber = reader.GetInt32(reader.GetOrdinal("SeasonNumber")),
                Title = reader.GetString(reader.GetOrdinal("Title")),
                CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
                CurrentEpisode = reader.GetInt32(reader.GetOrdinal("CurrentEpisode")),
                TotalEpisodes = reader.GetInt32(reader.GetOrdinal("TotalEpisodes")),
                Status = (MediaStatus)reader.GetInt32(reader.GetOrdinal("Status")),
                Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
                Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                AirDate = reader.IsDBNull(reader.GetOrdinal("AirDate")) ? null : reader.GetDateTime(reader.GetOrdinal("AirDate")),
                EpisodesData = reader.IsDBNull(reader.GetOrdinal("EpisodesData")) ? null : reader.GetString(reader.GetOrdinal("EpisodesData")),
                TvShowId = Guid.Parse(reader.GetString(reader.GetOrdinal("TvShowId"))),
            });
        return list;
    });
    public DbSetShim<MangaVolume> MangaVolumes => new(this, async (ct) =>
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM MangaVolumes;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<MangaVolume>();
        while (await reader.ReadAsync(ct))
            list.Add(new MangaVolume
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                VolumeNumber = reader.GetInt32(reader.GetOrdinal("VolumeNumber")),
                Title = reader.GetString(reader.GetOrdinal("Title")),
                CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
                CurrentPage = reader.GetInt32(reader.GetOrdinal("CurrentPage")),
                TotalPages = reader.GetInt32(reader.GetOrdinal("TotalPages")),
                CurrentChapter = reader.GetInt32(reader.GetOrdinal("CurrentChapter")),
                TotalChapters = reader.GetInt32(reader.GetOrdinal("TotalChapters")),
                Status = (MediaStatus)reader.GetInt32(reader.GetOrdinal("Status")),
                Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
                Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                ReleaseDate = reader.IsDBNull(reader.GetOrdinal("ReleaseDate")) ? null : reader.GetDateTime(reader.GetOrdinal("ReleaseDate")),
                MangaId = Guid.Parse(reader.GetString(reader.GetOrdinal("MangaId"))),
            });
        return list;
    });
    public DbSetShim<Franchise> Franchises => new(this, async (ct) => await GetAllFranchisesAsync(ct));
    public DbSetShim<CustomList> CustomLists => new(this, async (ct) => await GetCustomListsAsync(ct));
    public DbSetShim<CustomListItem> CustomListItems => new(this, async (ct) =>
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM CustomListItems;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<CustomListItem>();
        while (await reader.ReadAsync(ct))
            list.Add(new CustomListItem
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                ListId = Guid.Parse(reader.GetString(reader.GetOrdinal("ListId"))),
                MediaItemId = Guid.Parse(reader.GetString(reader.GetOrdinal("MediaItemId"))),
                Order = reader.GetInt32(reader.GetOrdinal("Order")),
                AddedAt = reader.GetDateTime(reader.GetOrdinal("AddedAt")),
            });
        return list;
    });
    public DbSetShim<MediaEvent> Events => new(this, async (ct) => await GetMediaEventsAsync(null, null, null, 1000, ct));
    public DbSetShim<MediaEvent> MediaEvents => Events;
    public DbSetShim<AppSetting> Settings => new(this, async (ct) =>
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Settings;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<AppSetting>();
        while (await reader.ReadAsync(ct))
            list.Add(new AppSetting
            {
                Key = reader.GetString(reader.GetOrdinal("Key")),
                Value = reader.GetString(reader.GetOrdinal("Value")),
                UpdatedAt = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
            });
        return list;
    });
    public DbSetShim<ApiToken> ApiTokens => new(this, async (ct) => await GetAllApiTokensAsync(ct));

    // ------------------------------------------------------------------
    // Dapper.AOT data access (media items)
    // ------------------------------------------------------------------

    /// <summary>Loads a single media item row plus its franchise, seasons and volumes.</summary>
    public async Task<MediaItem?> LoadMediaItemAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var idStr = id.ToString().ToUpperInvariant();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM MediaItems WHERE Id = @id;";
        cmd.Parameters.Add(new SqliteParameter("@id", idStr));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct))
        {
            return null;
        }

        var row = ReadMediaItemRow(reader);

        Franchise? franchise = null;
        if (row.FranchiseId != null)
        {
            using var fcmd = conn.CreateCommand();
            fcmd.CommandText = "SELECT * FROM Franchises WHERE Id = @id;";
            fcmd.Parameters.Add(new SqliteParameter("@id", row.FranchiseId!));
            using var freader = await fcmd.ExecuteReaderAsync(ct);
            if (await freader.ReadAsync(ct))
            {
                franchise = new Franchise
                {
                    Id = Guid.Parse(freader.GetString(freader.GetOrdinal("Id"))),
                    Name = freader.GetString(freader.GetOrdinal("Name")),
                    Description = freader.IsDBNull(freader.GetOrdinal("Description")) ? null : freader.GetString(freader.GetOrdinal("Description")),
                    CoverUrl = freader.IsDBNull(freader.GetOrdinal("CoverUrl")) ? null : freader.GetString(freader.GetOrdinal("CoverUrl")),
                };
            }
        }

        List<TvSeason>? seasons = null;
        if (row.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow)
        {
            seasons = await LoadTvSeasons(conn, idStr, ct);
        }

        List<MangaVolume>? volumes = null;
        if (row.MediaType == SqliteSchemaInitializer.MediaTypes.Manga)
        {
            volumes = await LoadMangaVolumes(conn, idStr, ct);
        }

        return row.ToEntity(franchise, seasons, volumes);
    }

    /// <summary>Pre-cached column ordinals for MediaItems rows.</summary>
    internal readonly struct MediaItemOrdinals(DbDataReader reader)
    {
        public readonly int Id = reader.GetOrdinal("Id");
        public readonly int Title = reader.GetOrdinal("Title");
        public readonly int Status = reader.GetOrdinal("Status");
        public readonly int Score = reader.GetOrdinal("Score");
        public readonly int DetailedScoreJson = reader.GetOrdinal("DetailedScoreJson");
        public readonly int StartedAt = reader.GetOrdinal("StartedAt");
        public readonly int FinishedAt = reader.GetOrdinal("FinishedAt");
        public readonly int LastActivityAt = reader.GetOrdinal("LastActivityAt");
        public readonly int Notes = reader.GetOrdinal("Notes");
        public readonly int DropReason = reader.GetOrdinal("DropReason");
        public readonly int DropNotes = reader.GetOrdinal("DropNotes");
        public readonly int QuotesJson = reader.GetOrdinal("QuotesJson");
        public readonly int Description = reader.GetOrdinal("Description");
        public readonly int TrailerVideoId = reader.GetOrdinal("TrailerVideoId");
        public readonly int CoverUrl = reader.GetOrdinal("CoverUrl");
        public readonly int CoversJson = reader.GetOrdinal("CoversJson");
        public readonly int CreatorImageUrl = reader.GetOrdinal("CreatorImageUrl");
        public readonly int SyncStatus = reader.GetOrdinal("SyncStatus");
        public readonly int CreatedAt = reader.GetOrdinal("CreatedAt");
        public readonly int UpdatedAt = reader.GetOrdinal("UpdatedAt");
        public readonly int FranchiseId = reader.GetOrdinal("FranchiseId");
        public readonly int FranchiseOrder = reader.GetOrdinal("FranchiseOrder");
        public readonly int ExternalId = reader.GetOrdinal("ExternalId");
        public readonly int ExternalSource = reader.GetOrdinal("ExternalSource");
        public readonly int ImportSource = reader.GetOrdinal("ImportSource");
        public readonly int ExternalRating = reader.GetOrdinal("ExternalRating");
        public readonly int ExternalRatingVotes = reader.GetOrdinal("ExternalRatingVotes");
        public readonly int ExternalRatingsJson = reader.GetOrdinal("ExternalRatingsJson");
        public readonly int NextAutoRefreshAt = reader.GetOrdinal("NextAutoRefreshAt");
        public readonly int AutoRefreshIntervalDays = reader.GetOrdinal("AutoRefreshIntervalDays");
        public readonly int LastAutoRefreshedAt = reader.GetOrdinal("LastAutoRefreshedAt");
        public readonly int ReleaseDate = reader.GetOrdinal("ReleaseDate");
        public readonly int ReleaseYear = reader.GetOrdinal("ReleaseYear");
        public readonly int EndDate = reader.GetOrdinal("EndDate");
        public readonly int WatchedOn = reader.GetOrdinal("WatchedOn");
        public readonly int ReleaseStatus = reader.GetOrdinal("ReleaseStatus");
        public readonly int OriginalLanguage = reader.GetOrdinal("OriginalLanguage");
        public readonly int CountryOfOrigin = reader.GetOrdinal("CountryOfOrigin");
        public readonly int OriginalTitle = reader.GetOrdinal("OriginalTitle");
        public readonly int CastJson = reader.GetOrdinal("CastJson");
        public readonly int StaffJson = reader.GetOrdinal("StaffJson");
        public readonly int TranslatedSynopsis = reader.GetOrdinal("TranslatedSynopsis");
        public readonly int TranslationLanguage = reader.GetOrdinal("TranslationLanguage");
        public readonly int Genres = reader.GetOrdinal("Genres");
        public readonly int Tags = reader.GetOrdinal("Tags");
        public readonly int UnlockedAchievements = reader.GetOrdinal("UnlockedAchievements");
        public readonly int UserPlatform = reader.GetOrdinal("UserPlatform");
        public readonly int RelatedMediaJson = reader.GetOrdinal("RelatedMediaJson");
        public readonly int PendingMatchesJson = reader.GetOrdinal("PendingMatchesJson");
        public readonly int RelatedSource = reader.GetOrdinal("RelatedSource");
        public readonly int AchievementsJson = reader.GetOrdinal("AchievementsJson");
        public readonly int RecommendationsJson = reader.GetOrdinal("RecommendationsJson");
        public readonly int RecommendationsUpdatedAt = reader.GetOrdinal("RecommendationsUpdatedAt");
        public readonly int IsCustomEdited = reader.GetOrdinal("IsCustomEdited");
        public readonly int MediaType = reader.GetOrdinal("MediaType");
        public readonly int Manga_Author = reader.GetOrdinal("Manga_Author");
        public readonly int Manga_RomajiTitle = reader.GetOrdinal("Manga_RomajiTitle");
        public readonly int Manga_Format = reader.GetOrdinal("Manga_Format");
        public readonly int CurrentVolume = reader.GetOrdinal("CurrentVolume");
        public readonly int Manga_TotalVolumes = reader.GetOrdinal("Manga_TotalVolumes");
        public readonly int Author = reader.GetOrdinal("Author");
        public readonly int CurrentPage = reader.GetOrdinal("CurrentPage");
        public readonly int TotalPages = reader.GetOrdinal("TotalPages");
        public readonly int CurrentChapter = reader.GetOrdinal("CurrentChapter");
        public readonly int TotalChapters = reader.GetOrdinal("TotalChapters");
        public readonly int DurationMinutes = reader.GetOrdinal("DurationMinutes");
        public readonly int Director = reader.GetOrdinal("Director");
        public readonly int Movie_IsAnime = reader.GetOrdinal("Movie_IsAnime");
        public readonly int Movie_Studio = reader.GetOrdinal("Movie_Studio");
        public readonly int Movie_RomajiTitle = reader.GetOrdinal("Movie_RomajiTitle");
        public readonly int Network = reader.GetOrdinal("Network");
        public readonly int TvShow_IsAnime = reader.GetOrdinal("TvShow_IsAnime");
        public readonly int TvShow_Studio = reader.GetOrdinal("TvShow_Studio");
        public readonly int TvShow_RomajiTitle = reader.GetOrdinal("TvShow_RomajiTitle");
        public readonly int TvShow_EpisodeDurationMinutes = reader.GetOrdinal("TvShow_EpisodeDurationMinutes");
        public readonly int Platform = reader.GetOrdinal("Platform");
        public readonly int HoursPlayed = reader.GetOrdinal("HoursPlayed");
        public readonly int Studio = reader.GetOrdinal("Studio");
    }

    internal static MediaItemRow ReadMediaItemRow(DbDataReader reader)
    {
        return ReadMediaItemRow(reader, new MediaItemOrdinals(reader));
    }

    internal static MediaItemRow ReadMediaItemRow(DbDataReader reader, in MediaItemOrdinals ordinals)
    {
        return new MediaItemRow
        {
            Id = reader.GetString(ordinals.Id),
            Title = reader.GetString(ordinals.Title),
            Status = reader.GetInt32(ordinals.Status),
            Score = reader.IsDBNull(ordinals.Score) ? null : reader.GetInt32(ordinals.Score),
            DetailedScoreJson = reader.IsDBNull(ordinals.DetailedScoreJson) ? null : reader.GetString(ordinals.DetailedScoreJson),
            StartedAt = ReadNullableDateTime(reader, ordinals.StartedAt),
            FinishedAt = ReadNullableDateTime(reader, ordinals.FinishedAt),
            LastActivityAt = ReadNullableDateTime(reader, ordinals.LastActivityAt),
            Notes = reader.IsDBNull(ordinals.Notes) ? null : reader.GetString(ordinals.Notes),
            DropReason = reader.IsDBNull(ordinals.DropReason) ? null : reader.GetString(ordinals.DropReason),
            DropNotes = reader.IsDBNull(ordinals.DropNotes) ? null : reader.GetString(ordinals.DropNotes),
            QuotesJson = reader.IsDBNull(ordinals.QuotesJson) ? null : reader.GetString(ordinals.QuotesJson),
            Description = reader.IsDBNull(ordinals.Description) ? null : reader.GetString(ordinals.Description),
            TrailerVideoId = reader.IsDBNull(ordinals.TrailerVideoId) ? null : reader.GetString(ordinals.TrailerVideoId),
            CoverUrl = reader.IsDBNull(ordinals.CoverUrl) ? null : reader.GetString(ordinals.CoverUrl),
            CoversJson = reader.IsDBNull(ordinals.CoversJson) ? null : reader.GetString(ordinals.CoversJson),
            CreatorImageUrl = reader.IsDBNull(ordinals.CreatorImageUrl) ? null : reader.GetString(ordinals.CreatorImageUrl),
            SyncStatus = (SyncStatus)reader.GetInt32(ordinals.SyncStatus),
            CreatedAt = reader.GetDateTime(ordinals.CreatedAt),
            UpdatedAt = reader.GetDateTime(ordinals.UpdatedAt),
            FranchiseId = reader.IsDBNull(ordinals.FranchiseId) ? null : reader.GetString(ordinals.FranchiseId),
            FranchiseOrder = reader.IsDBNull(ordinals.FranchiseOrder) ? null : reader.GetInt32(ordinals.FranchiseOrder),
            ExternalId = reader.IsDBNull(ordinals.ExternalId) ? null : reader.GetString(ordinals.ExternalId),
            ExternalSource = reader.IsDBNull(ordinals.ExternalSource) ? null : reader.GetString(ordinals.ExternalSource),
            ImportSource = reader.IsDBNull(ordinals.ImportSource) ? null : reader.GetString(ordinals.ImportSource),
            ExternalRating = reader.IsDBNull(ordinals.ExternalRating) ? null : reader.GetDouble(ordinals.ExternalRating),
            ExternalRatingVotes = reader.IsDBNull(ordinals.ExternalRatingVotes) ? null : reader.GetInt32(ordinals.ExternalRatingVotes),
            ExternalRatingsJson = reader.IsDBNull(ordinals.ExternalRatingsJson) ? null : reader.GetString(ordinals.ExternalRatingsJson),
            NextAutoRefreshAt = ReadNullableDateTime(reader, ordinals.NextAutoRefreshAt),
            AutoRefreshIntervalDays = reader.GetInt32(ordinals.AutoRefreshIntervalDays),
            LastAutoRefreshedAt = ReadNullableDateTime(reader, ordinals.LastAutoRefreshedAt),
            ReleaseDate = ReadNullableDateTime(reader, ordinals.ReleaseDate),
            ReleaseYear = reader.IsDBNull(ordinals.ReleaseYear) ? null : reader.GetInt32(ordinals.ReleaseYear),
            EndDate = ReadNullableDateTime(reader, ordinals.EndDate),
            WatchedOn = reader.IsDBNull(ordinals.WatchedOn) ? null : reader.GetString(ordinals.WatchedOn),
            ReleaseStatus = reader.IsDBNull(ordinals.ReleaseStatus) ? null : reader.GetString(ordinals.ReleaseStatus),
            OriginalLanguage = reader.IsDBNull(ordinals.OriginalLanguage) ? null : reader.GetString(ordinals.OriginalLanguage),
            CountryOfOrigin = reader.IsDBNull(ordinals.CountryOfOrigin) ? null : reader.GetString(ordinals.CountryOfOrigin),
            OriginalTitle = reader.IsDBNull(ordinals.OriginalTitle) ? null : reader.GetString(ordinals.OriginalTitle),
            CastJson = reader.IsDBNull(ordinals.CastJson) ? null : reader.GetString(ordinals.CastJson),
            StaffJson = reader.IsDBNull(ordinals.StaffJson) ? null : reader.GetString(ordinals.StaffJson),
            TranslatedSynopsis = reader.IsDBNull(ordinals.TranslatedSynopsis) ? null : reader.GetString(ordinals.TranslatedSynopsis),
            TranslationLanguage = reader.IsDBNull(ordinals.TranslationLanguage) ? null : reader.GetString(ordinals.TranslationLanguage),
            Genres = reader.IsDBNull(ordinals.Genres) ? null : reader.GetString(ordinals.Genres),
            Tags = reader.IsDBNull(ordinals.Tags) ? null : reader.GetString(ordinals.Tags),
            UnlockedAchievements = reader.IsDBNull(ordinals.UnlockedAchievements) ? null : reader.GetString(ordinals.UnlockedAchievements),
            UserPlatform = reader.IsDBNull(ordinals.UserPlatform) ? null : reader.GetString(ordinals.UserPlatform),
            RelatedMediaJson = reader.IsDBNull(ordinals.RelatedMediaJson) ? null : reader.GetString(ordinals.RelatedMediaJson),
            PendingMatchesJson = reader.IsDBNull(ordinals.PendingMatchesJson) ? null : reader.GetString(ordinals.PendingMatchesJson),
            RelatedSource = reader.IsDBNull(ordinals.RelatedSource) ? null : reader.GetString(ordinals.RelatedSource),
            AchievementsJson = reader.IsDBNull(ordinals.AchievementsJson) ? null : reader.GetString(ordinals.AchievementsJson),
            RecommendationsJson = reader.IsDBNull(ordinals.RecommendationsJson) ? null : reader.GetString(ordinals.RecommendationsJson),
            RecommendationsUpdatedAt = ReadNullableDateTime(reader, ordinals.RecommendationsUpdatedAt),
            IsCustomEdited = reader.GetBoolean(ordinals.IsCustomEdited),
            MediaType = NormalizeMediaType(reader.GetString(ordinals.MediaType)),
            Author = NormalizeMediaType(reader.GetString(ordinals.MediaType)) == SqliteSchemaInitializer.MediaTypes.Manga
                ? (reader.IsDBNull(ordinals.Manga_Author)
                    ? (reader.IsDBNull(ordinals.Author) ? null : reader.GetString(ordinals.Author))
                    : reader.GetString(ordinals.Manga_Author))
                : (reader.IsDBNull(ordinals.Author) ? null : reader.GetString(ordinals.Author)),
            CurrentPage = reader.IsDBNull(ordinals.CurrentPage) ? null : reader.GetInt32(ordinals.CurrentPage),
            TotalPages = reader.IsDBNull(ordinals.TotalPages) ? null : reader.GetInt32(ordinals.TotalPages),
            CurrentChapter = reader.IsDBNull(ordinals.CurrentChapter) ? null : reader.GetInt32(ordinals.CurrentChapter),
            TotalChapters = reader.IsDBNull(ordinals.TotalChapters) ? null : reader.GetInt32(ordinals.TotalChapters),
            Manga_Author = reader.IsDBNull(ordinals.Manga_Author) ? null : reader.GetString(ordinals.Manga_Author),
            Manga_RomajiTitle = reader.IsDBNull(ordinals.Manga_RomajiTitle) ? null : reader.GetString(ordinals.Manga_RomajiTitle),
            Manga_Format = reader.IsDBNull(ordinals.Manga_Format) ? null : reader.GetString(ordinals.Manga_Format),
            CurrentVolume = reader.IsDBNull(ordinals.CurrentVolume) ? null : reader.GetInt32(ordinals.CurrentVolume),
            Manga_TotalVolumes = reader.IsDBNull(ordinals.Manga_TotalVolumes) ? null : reader.GetInt32(ordinals.Manga_TotalVolumes),
            DurationMinutes = reader.IsDBNull(ordinals.DurationMinutes) ? null : reader.GetInt32(ordinals.DurationMinutes),
            Director = reader.IsDBNull(ordinals.Director) ? null : reader.GetString(ordinals.Director),
            Movie_IsAnime = reader.IsDBNull(ordinals.Movie_IsAnime) ? null : reader.GetBoolean(ordinals.Movie_IsAnime),
            Movie_Studio = reader.IsDBNull(ordinals.Movie_Studio) ? null : reader.GetString(ordinals.Movie_Studio),
            Movie_RomajiTitle = reader.IsDBNull(ordinals.Movie_RomajiTitle) ? null : reader.GetString(ordinals.Movie_RomajiTitle),
            Network = reader.IsDBNull(ordinals.Network) ? null : reader.GetString(ordinals.Network),
            TvShow_IsAnime = reader.IsDBNull(ordinals.TvShow_IsAnime) ? null : reader.GetBoolean(ordinals.TvShow_IsAnime),
            TvShow_Studio = reader.IsDBNull(ordinals.TvShow_Studio) ? null : reader.GetString(ordinals.TvShow_Studio),
            TvShow_RomajiTitle = reader.IsDBNull(ordinals.TvShow_RomajiTitle) ? null : reader.GetString(ordinals.TvShow_RomajiTitle),
            TvShow_EpisodeDurationMinutes = reader.IsDBNull(ordinals.TvShow_EpisodeDurationMinutes) ? null : reader.GetInt32(ordinals.TvShow_EpisodeDurationMinutes),
            Platform = reader.IsDBNull(ordinals.Platform) ? null : reader.GetString(ordinals.Platform),
            HoursPlayed = reader.IsDBNull(ordinals.HoursPlayed) ? null : reader.GetInt32(ordinals.HoursPlayed),
            Studio = reader.IsDBNull(ordinals.Studio) ? null : reader.GetString(ordinals.Studio),
        };
    }

    private static DateTime? ReadNullableDateTime(DbDataReader reader, string columnName)
    {
        return ReadNullableDateTime(reader, reader.GetOrdinal(columnName));
    }

    private static DateTime? ReadNullableDateTime(DbDataReader reader, int ordinal)
    {
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    // Older rows / imports can carry "manga", "MOVIE", etc. The rest of the code switches on the
    // canonical spelling, so normalise once at the read boundary.
    private static string NormalizeMediaType(string value) => value.Trim().ToLowerInvariant() switch
    {
        "game" => SqliteSchemaInitializer.MediaTypes.Game,
        "book" => SqliteSchemaInitializer.MediaTypes.Book,
        "manga" => SqliteSchemaInitializer.MediaTypes.Manga,
        "movie" => SqliteSchemaInitializer.MediaTypes.Movie,
        "tvshow" => SqliteSchemaInitializer.MediaTypes.TvShow,
        _ => value,
    };

    internal static async Task<List<TvSeason>> LoadTvSeasons(DbConnection conn, string tvShowId, CancellationToken ct)
    {
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM TvSeasons WHERE TvShowId = @id ORDER BY SeasonNumber;";
        cmd.Parameters.Add(new SqliteParameter("@id", tvShowId));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<TvSeason>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new TvSeason
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                SeasonNumber = reader.GetInt32(reader.GetOrdinal("SeasonNumber")),
                Title = reader.GetString(reader.GetOrdinal("Title")),
                CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
                CurrentEpisode = reader.GetInt32(reader.GetOrdinal("CurrentEpisode")),
                TotalEpisodes = reader.GetInt32(reader.GetOrdinal("TotalEpisodes")),
                Status = (MediaStatus)reader.GetInt32(reader.GetOrdinal("Status")),
                Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
                Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                AirDate = ReadNullableDateTime(reader, "AirDate"),
                EpisodesData = reader.IsDBNull(reader.GetOrdinal("EpisodesData")) ? null : reader.GetString(reader.GetOrdinal("EpisodesData")),
                TvShowId = Guid.Parse(reader.GetString(reader.GetOrdinal("TvShowId"))),
            });
        }
        return list;
    }

    internal static async Task<List<MangaVolume>> LoadMangaVolumes(DbConnection conn, string mangaId, CancellationToken ct)
    {
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM MangaVolumes WHERE MangaId = @id ORDER BY VolumeNumber;";
        cmd.Parameters.Add(new SqliteParameter("@id", mangaId));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<MangaVolume>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new MangaVolume
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                VolumeNumber = reader.GetInt32(reader.GetOrdinal("VolumeNumber")),
                Title = reader.GetString(reader.GetOrdinal("Title")),
                CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
                CurrentPage = reader.GetInt32(reader.GetOrdinal("CurrentPage")),
                TotalPages = reader.GetInt32(reader.GetOrdinal("TotalPages")),
                CurrentChapter = reader.GetInt32(reader.GetOrdinal("CurrentChapter")),
                TotalChapters = reader.GetInt32(reader.GetOrdinal("TotalChapters")),
                Status = (MediaStatus)reader.GetInt32(reader.GetOrdinal("Status")),
                Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
                Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                ReleaseDate = ReadNullableDateTime(reader, "ReleaseDate"),
                MangaId = Guid.Parse(reader.GetString(reader.GetOrdinal("MangaId"))),
            });
        }
        return list;
    }

    /// <summary>Loads media items with filtering, sorting and franchise included.</summary>
    public async Task<List<MediaItem>> LoadMediaItemsAsync(
        string? mediaType,
        MediaStatus? status,
        bool? isAnime,
        string? search,
        string? sortBy,
        string? sortOrder,
        CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var cmd = conn.CreateCommand();
        var sb = new System.Text.StringBuilder(@"
            SELECT m.*, f.Id as FranchiseId, f.Name as FranchiseName, f.Description as FranchiseDescription, f.CoverUrl as FranchiseCoverUrl
            FROM MediaItems m
            LEFT JOIN Franchises f ON m.FranchiseId = f.Id
            WHERE 1=1");
        var paramIndex = 0;

        if (!string.IsNullOrEmpty(mediaType))
        {
            sb.Append(" AND LOWER(m.MediaType) = LOWER(@p").Append(paramIndex).Append(')');
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", mediaType));
            paramIndex++;
        }

        if (status is { } s)
        {
            sb.Append(" AND m.Status = @p").Append(paramIndex);
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", (int)s));
            paramIndex++;
        }

        if (isAnime is { } anime)
        {
            // The type columns are nullable, so "not anime" must treat NULL as false; a plain
            // equality would silently drop rows that never had the flag written.
            sb.Append(anime
                ? " AND (m.Movie_IsAnime = 1 OR m.TvShow_IsAnime = 1)"
                : " AND (COALESCE(m.Movie_IsAnime, 0) = 0 AND COALESCE(m.TvShow_IsAnime, 0) = 0)");
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            sb.Append(" AND (m.Title LIKE @p").Append(paramIndex);
            sb.Append(" OR f.Name LIKE @p").Append(paramIndex + 1);
            sb.Append(" OR m.Movie_RomajiTitle LIKE @p").Append(paramIndex + 2);
            sb.Append(" OR m.TvShow_RomajiTitle LIKE @p").Append(paramIndex + 3).Append(')');
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", $"%{search}%"));
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex + 1}", $"%{search}%"));
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex + 2}", $"%{search}%"));
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex + 3}", $"%{search}%"));
            paramIndex += 4;
        }

        var orderBy = sortBy?.Trim()?.ToLowerInvariant() switch
        {
            "score" => "CASE WHEN m.Score IS NULL THEN 1 ELSE 0 END, m.Score",
            "title" => "m.Title",
            _ => "m.CreatedAt"
        };
        var orderDir = string.Equals(sortOrder, "asc", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
        sb.Append(" ORDER BY ").Append(orderBy).Append(' ').Append(orderDir);

        cmd.CommandText = sb.ToString();
        using var reader = await cmd.ExecuteReaderAsync(ct);

        var rows = new List<MediaItemRow>();
        var ordinals = new MediaItemOrdinals(reader);
        while (await reader.ReadAsync(ct))
        {
            rows.Add(ReadMediaItemRow(reader, in ordinals));
        }

        // Collect distinct franchise IDs and load in one batch.
        var franchiseIds = rows.Where(r => r.FranchiseId != null).Select(r => r.FranchiseId!.ToUpperInvariant()).Distinct().ToList();
        var franchises = new Dictionary<string, Franchise>(StringComparer.OrdinalIgnoreCase);
        if (franchiseIds.Count > 0)
        {
            var franCmd = conn.CreateCommand();
            franCmd.CommandText = $"SELECT * FROM Franchises WHERE Id IN ({string.Join(",", franchiseIds.Select((_, i) => $"@fid{i}"))})";
            for (var i = 0; i < franchiseIds.Count; i++)
                franCmd.Parameters.Add(new SqliteParameter($"@fid{i}", franchiseIds[i]));
            using var franReader = await franCmd.ExecuteReaderAsync(ct);
            while (await franReader.ReadAsync(ct))
            {
                var f = new Franchise
                {
                    Id = Guid.Parse(franReader.GetString(franReader.GetOrdinal("Id"))),
                    Name = franReader.GetString(franReader.GetOrdinal("Name")),
                    Description = franReader.IsDBNull(franReader.GetOrdinal("Description")) ? null : franReader.GetString(franReader.GetOrdinal("Description")),
                    CoverUrl = franReader.IsDBNull(franReader.GetOrdinal("CoverUrl")) ? null : franReader.GetString(franReader.GetOrdinal("CoverUrl")),
                };
                franchises[f.Id.ToString().ToUpperInvariant()] = f;
            }
        }

        // Manga keeps scalar chapter/volume columns directly on the MediaItems row, so its
        // volumes are intentionally NOT loaded here (that caused N round-trips and freezes for
        // large manga categories). TvShow.TotalEpisodesCount / TotalEpisodesWatched / Seasons.Count
        // are COMPUTED from the Seasons list, not stored flat, so load all TV-show seasons in ONE
        // batched query instead of per-show round-trips.
        var seasonMap = new Dictionary<string, List<TvSeason>>(StringComparer.OrdinalIgnoreCase);
        var showIds = rows.Where(r => r.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow)
            .Select(r => r.Id.ToUpperInvariant()).Distinct().ToList();
        if (showIds.Count > 0)
        {
            seasonMap = await LoadTvSeasonsBatch(conn, showIds, ct);
        }

        var items = new List<MediaItem>(rows.Count);
        foreach (var row in rows)
        {
            var franchise = row.FranchiseId != null && franchises.TryGetValue(row.FranchiseId.ToUpperInvariant(), out var f) ? f : null;
            List<TvSeason>? seasons = null;
            if (row.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow &&
                seasonMap.TryGetValue(row.Id.ToUpperInvariant(), out var found))
            {
                seasons = found;
            }
            items.Add(row.ToEntity(franchise, seasons, null));
        }

        return items;
    }

    /// <summary>Loads seasons for many TV shows in one batched query, chunked to stay inside
    /// SQLite's parameter limit.</summary>
    private static async Task<Dictionary<string, List<TvSeason>>> LoadTvSeasonsBatch(
        DbConnection conn, IReadOnlyList<string> tvShowIds, CancellationToken ct)
    {
        var result = new Dictionary<string, List<TvSeason>>(StringComparer.OrdinalIgnoreCase);
        foreach (var chunk in tvShowIds.Chunk(500))
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"SELECT * FROM TvSeasons WHERE TvShowId IN ({string.Join(",", chunk.Select((_, i) => $"@sid{i}"))}) ORDER BY TvShowId, SeasonNumber;";
            for (var i = 0; i < chunk.Length; i++)
                cmd.Parameters.Add(new SqliteParameter($"@sid{i}", chunk[i]));
            using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var season = new TvSeason
                {
                    Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                    SeasonNumber = reader.GetInt32(reader.GetOrdinal("SeasonNumber")),
                    Title = reader.GetString(reader.GetOrdinal("Title")),
                    CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
                    CurrentEpisode = reader.GetInt32(reader.GetOrdinal("CurrentEpisode")),
                    TotalEpisodes = reader.GetInt32(reader.GetOrdinal("TotalEpisodes")),
                    Status = (MediaStatus)reader.GetInt32(reader.GetOrdinal("Status")),
                    Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
                    Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                    AirDate = ReadNullableDateTime(reader, "AirDate"),
                    EpisodesData = reader.IsDBNull(reader.GetOrdinal("EpisodesData")) ? null : reader.GetString(reader.GetOrdinal("EpisodesData")),
                    TvShowId = Guid.Parse(reader.GetString(reader.GetOrdinal("TvShowId"))),
                };
                var key = season.TvShowId.ToString().ToUpperInvariant();
                if (!result.TryGetValue(key, out var list))
                {
                    list = [];
                    result[key] = list;
                }
                list.Add(season);
            }
        }
        return result;
    }

    /// <summary>Inserts a media item row (entity must already have Id set).</summary>
    public async Task InsertMediaItemAsync(MediaItem item, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var row = MediaItemRow.FromEntity(item);
        var result = await conn.ExecuteAsync(
            """
            INSERT INTO MediaItems (
                Id, Title, Status, Score, DetailedScoreJson, StartedAt, FinishedAt, LastActivityAt,
                Notes, DropReason, DropNotes, QuotesJson, Description, TrailerVideoId, CoverUrl,
                CoversJson, CreatorImageUrl, SyncStatus, CreatedAt, UpdatedAt, FranchiseId, FranchiseOrder,
                ExternalId, ExternalSource, ImportSource, ExternalRating, ExternalRatingVotes,
                ExternalRatingsJson, NextAutoRefreshAt, AutoRefreshIntervalDays, LastAutoRefreshedAt,
                ReleaseDate, ReleaseYear, EndDate, WatchedOn, ReleaseStatus, OriginalLanguage,
                CountryOfOrigin, OriginalTitle, CastJson, StaffJson, TranslatedSynopsis,
                TranslationLanguage, Genres, Tags, UnlockedAchievements, UserPlatform,
                RelatedMediaJson, PendingMatchesJson, RelatedSource, AchievementsJson,
                RecommendationsJson, RecommendationsUpdatedAt, IsCustomEdited, MediaType,
                Author, CurrentPage, TotalPages, CurrentChapter, TotalChapters,
                Manga_Author, Manga_RomajiTitle, Manga_Format, CurrentVolume, Manga_TotalVolumes,
                DurationMinutes, Director, Movie_IsAnime, Movie_Studio, Movie_RomajiTitle,
                Network, TvShow_IsAnime, TvShow_Studio, TvShow_RomajiTitle, TvShow_EpisodeDurationMinutes,
                Platform, HoursPlayed, Studio
            ) VALUES (
                @Id, @Title, @Status, @Score, @DetailedScoreJson, @StartedAt, @FinishedAt, @LastActivityAt,
                @Notes, @DropReason, @DropNotes, @QuotesJson, @Description, @TrailerVideoId, @CoverUrl,
                @CoversJson, @CreatorImageUrl, @SyncStatus, @CreatedAt, @UpdatedAt, @FranchiseId, @FranchiseOrder,
                @ExternalId, @ExternalSource, @ImportSource, @ExternalRating, @ExternalRatingVotes,
                @ExternalRatingsJson, @NextAutoRefreshAt, @AutoRefreshIntervalDays, @LastAutoRefreshedAt,
                @ReleaseDate, @ReleaseYear, @EndDate, @WatchedOn, @ReleaseStatus, @OriginalLanguage,
                @CountryOfOrigin, @OriginalTitle, @CastJson, @StaffJson, @TranslatedSynopsis,
                @TranslationLanguage, @Genres, @Tags, @UnlockedAchievements, @UserPlatform,
                @RelatedMediaJson, @PendingMatchesJson, @RelatedSource, @AchievementsJson,
                @RecommendationsJson, @RecommendationsUpdatedAt, @IsCustomEdited, @MediaType,
                @Author, @CurrentPage, @TotalPages, @CurrentChapter, @TotalChapters,
                @Manga_Author, @Manga_RomajiTitle, @Manga_Format, @CurrentVolume, @Manga_TotalVolumes,
                @DurationMinutes, @Director, @Movie_IsAnime, @Movie_Studio, @Movie_RomajiTitle,
                @Network, @TvShow_IsAnime, @TvShow_Studio, @TvShow_RomajiTitle, @TvShow_EpisodeDurationMinutes,
                @Platform, @HoursPlayed, @Studio
            );
            """,
            row);
    }

    /// <summary>Fully updates a media item row.</summary>
    public async Task<int> UpdateMediaItemAsync(MediaItem item, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var row = MediaItemRow.FromEntity(item);
        var result = await conn.ExecuteAsync(
            """
            UPDATE MediaItems SET
                Title = @Title, Status = @Status, Score = @Score, DetailedScoreJson = @DetailedScoreJson,
                StartedAt = @StartedAt, FinishedAt = @FinishedAt, LastActivityAt = @LastActivityAt,
                Notes = @Notes, DropReason = @DropReason, DropNotes = @DropNotes, QuotesJson = @QuotesJson,
                Description = @Description, TrailerVideoId = @TrailerVideoId, CoverUrl = @CoverUrl,
                CoversJson = @CoversJson, CreatorImageUrl = @CreatorImageUrl, SyncStatus = @SyncStatus, UpdatedAt = @UpdatedAt,
                FranchiseId = @FranchiseId, FranchiseOrder = @FranchiseOrder, ExternalId = @ExternalId,
                ExternalSource = @ExternalSource, ImportSource = @ImportSource, ExternalRating = @ExternalRating,
                ExternalRatingVotes = @ExternalRatingVotes, ExternalRatingsJson = @ExternalRatingsJson,
                NextAutoRefreshAt = @NextAutoRefreshAt, AutoRefreshIntervalDays = @AutoRefreshIntervalDays,
                LastAutoRefreshedAt = @LastAutoRefreshedAt, ReleaseDate = @ReleaseDate, ReleaseYear = @ReleaseYear,
                EndDate = @EndDate, WatchedOn = @WatchedOn, ReleaseStatus = @ReleaseStatus,
                OriginalLanguage = @OriginalLanguage, CountryOfOrigin = @CountryOfOrigin,
                OriginalTitle = @OriginalTitle, CastJson = @CastJson, StaffJson = @StaffJson,
                TranslatedSynopsis = @TranslatedSynopsis, TranslationLanguage = @TranslationLanguage,
                Genres = @Genres, Tags = @Tags, UnlockedAchievements = @UnlockedAchievements,
                UserPlatform = @UserPlatform, RelatedMediaJson = @RelatedMediaJson,
                PendingMatchesJson = @PendingMatchesJson, RelatedSource = @RelatedSource,
                AchievementsJson = @AchievementsJson, RecommendationsJson = @RecommendationsJson,
                RecommendationsUpdatedAt = @RecommendationsUpdatedAt, IsCustomEdited = @IsCustomEdited,
                MediaType = @MediaType, Author = @Author, CurrentPage = @CurrentPage,
                TotalPages = @TotalPages, CurrentChapter = @CurrentChapter, TotalChapters = @TotalChapters,
                Manga_Author = @Manga_Author, Manga_RomajiTitle = @Manga_RomajiTitle,
                Manga_Format = @Manga_Format, CurrentVolume = @CurrentVolume,
                Manga_TotalVolumes = @Manga_TotalVolumes, DurationMinutes = @DurationMinutes,
                Director = @Director, Movie_IsAnime = @Movie_IsAnime, Movie_Studio = @Movie_Studio,
                Movie_RomajiTitle = @Movie_RomajiTitle, Network = @Network,
                TvShow_IsAnime = @TvShow_IsAnime, TvShow_Studio = @TvShow_Studio,
                TvShow_RomajiTitle = @TvShow_RomajiTitle,
                TvShow_EpisodeDurationMinutes = @TvShow_EpisodeDurationMinutes,
                Platform = @Platform, HoursPlayed = @HoursPlayed, Studio = @Studio
            WHERE Id = @Id;
            """,
            row);
        return result;
    }

    /// <summary>Deletes a media item row and its dependent rows (seasons, volumes, events, list items).</summary>
    public async Task<int> DeleteMediaItemAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var idStr = id.ToString().ToUpperInvariant();
        await conn.ExecuteAsync("DELETE FROM Events WHERE MediaId = @id;", new { id = idStr });
        await conn.ExecuteAsync("DELETE FROM TvSeasons WHERE TvShowId = @id;", new { id = idStr });
        await conn.ExecuteAsync("DELETE FROM MangaVolumes WHERE MangaId = @id;", new { id = idStr });
        await conn.ExecuteAsync("DELETE FROM CustomListItems WHERE MediaItemId = @id;", new { id = idStr });
        return await conn.ExecuteAsync("DELETE FROM MediaItems WHERE Id = @id;", new { id = idStr });
    }

    /// <summary>Inserts or updates a TV season.</summary>
    public async Task InsertTvSeasonAsync(TvSeason season, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO TvSeasons (Id, SeasonNumber, Title, CoverUrl, CurrentEpisode, TotalEpisodes,
                Status, Score, Notes, AirDate, EpisodesData, TvShowId)
            VALUES (@Id, @SeasonNumber, @Title, @CoverUrl, @CurrentEpisode, @TotalEpisodes,
                @Status, @Score, @Notes, @AirDate, @EpisodesData, @TvShowId)
            ON CONFLICT(Id) DO UPDATE SET
                SeasonNumber = excluded.SeasonNumber, Title = excluded.Title,
                CoverUrl = excluded.CoverUrl, CurrentEpisode = excluded.CurrentEpisode,
                TotalEpisodes = excluded.TotalEpisodes, Status = excluded.Status,
                Score = excluded.Score, Notes = excluded.Notes, AirDate = excluded.AirDate,
                EpisodesData = excluded.EpisodesData;
            """,
            new
            {
                Id = season.Id.ToString().ToUpperInvariant(),
                season.SeasonNumber,
                season.Title,
                season.CoverUrl,
                season.CurrentEpisode,
                season.TotalEpisodes,
                season.Status,
                season.Score,
                season.Notes,
                season.AirDate,
                season.EpisodesData,
                TvShowId = season.TvShowId.ToString().ToUpperInvariant(),
            });
    }

    /// <summary>Inserts or updates a manga volume.</summary>
    public async Task InsertMangaVolumeAsync(MangaVolume volume, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO MangaVolumes (Id, VolumeNumber, Title, CoverUrl, CurrentPage, TotalPages,
                CurrentChapter, TotalChapters, Status, Score, Notes, ReleaseDate, MangaId)
            VALUES (@Id, @VolumeNumber, @Title, @CoverUrl, @CurrentPage, @TotalPages,
                @CurrentChapter, @TotalChapters, @Status, @Score, @Notes, @ReleaseDate, @MangaId)
            ON CONFLICT(Id) DO UPDATE SET
                VolumeNumber = excluded.VolumeNumber, Title = excluded.Title,
                CoverUrl = excluded.CoverUrl, CurrentPage = excluded.CurrentPage,
                TotalPages = excluded.TotalPages, CurrentChapter = excluded.CurrentChapter,
                TotalChapters = excluded.TotalChapters, Status = excluded.Status,
                Score = excluded.Score, Notes = excluded.Notes, ReleaseDate = excluded.ReleaseDate;
            """,
            new
            {
                Id = volume.Id.ToString().ToUpperInvariant(),
                volume.VolumeNumber,
                volume.Title,
                CoverUrl = volume.CoverUrl,
                volume.CurrentPage,
                volume.TotalPages,
                volume.CurrentChapter,
                volume.TotalChapters,
                volume.Status,
                volume.Score,
                volume.Notes,
                volume.ReleaseDate,
                MangaId = volume.MangaId.ToString().ToUpperInvariant(),
            });
    }

    /// <summary>Inserts a media event.</summary>
    public async Task InsertMediaEventAsync(MediaEvent evt, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO Events (Id, MediaId, Type, OldValue, NewValue, CreatedAt)
            VALUES (@Id, @MediaId, @Type, @OldValue, @NewValue, @CreatedAt);
            """,
            new
            {
                Id = evt.Id.ToString().ToUpperInvariant(),
                MediaId = evt.MediaId.ToString().ToUpperInvariant(),
                evt.Type,
                evt.OldValue,
                evt.NewValue,
                CreatedAt = evt.CreatedAt.ToString("o"),
            });
    }

    // ------------------------------------------------------------------
    // Settings (AppSetting)
    // ------------------------------------------------------------------

    /// <summary>Reads a single setting value by key.</summary>
    public async Task<string?> GetSettingAsync(string key, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT Value FROM Settings WHERE Key = @key;";
        cmd.Parameters.Add(new SqliteParameter("@key", key));
        var result = await cmd.ExecuteScalarAsync(ct);
        return result is string s ? s : null;
    }

    /// <summary>Upserts a single setting.</summary>
    public async Task SetSettingAsync(string key, string value, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO Settings (Key, Value, UpdatedAt) VALUES (@key, @value, @updatedAt)
            ON CONFLICT(Key) DO UPDATE SET Value = @value, UpdatedAt = @updatedAt;
            """,
            new { key, value, updatedAt = DateTime.UtcNow });
    }

    /// <summary>Deletes a single setting by key.</summary>
    public async Task<int> DeleteSettingAsync(string key, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        return await conn.ExecuteAsync("DELETE FROM Settings WHERE Key = @key;", new { key });
    }

    // ------------------------------------------------------------------
    // ApiTokens
    // ------------------------------------------------------------------

    /// <summary>Finds an API token by its hash.</summary>
    public async Task<ApiToken?> GetApiTokenByHashAsync(string tokenHash, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ApiTokens WHERE TokenHash = @hash;";
        cmd.Parameters.Add(new SqliteParameter("@hash", tokenHash));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;

        return new ApiToken
        {
            Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
            Name = reader.GetString(reader.GetOrdinal("Name")),
            TokenHash = reader.GetString(reader.GetOrdinal("TokenHash")),
            TokenPrefix = reader.GetString(reader.GetOrdinal("TokenPrefix")),
            CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
            LastUsedAt = reader.IsDBNull(reader.GetOrdinal("LastUsedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("LastUsedAt")),
            ExpiresAt = reader.IsDBNull(reader.GetOrdinal("ExpiresAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ExpiresAt")),
        };
    }

    /// <summary>Returns all API tokens.</summary>
    public async Task<List<ApiToken>> GetAllApiTokensAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ApiTokens ORDER BY CreatedAt DESC;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<ApiToken>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new ApiToken
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                TokenHash = reader.GetString(reader.GetOrdinal("TokenHash")),
                TokenPrefix = reader.GetString(reader.GetOrdinal("TokenPrefix")),
                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                LastUsedAt = reader.IsDBNull(reader.GetOrdinal("LastUsedAt")) ? null : reader.GetDateTime(reader.GetOrdinal("LastUsedAt")),
                ExpiresAt = reader.IsDBNull(reader.GetOrdinal("ExpiresAt")) ? null : reader.GetDateTime(reader.GetOrdinal("ExpiresAt")),
            });
        }
        return list;
    }

    /// <summary>Updates the LastUsedAt of an API token.</summary>
    public async Task UpdateApiTokenLastUsedAsync(Guid id, DateTime? lastUsed, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            "UPDATE ApiTokens SET LastUsedAt = @lastUsed WHERE Id = @id;",
            new { id = id.ToString().ToUpperInvariant(), lastUsed });
    }

    /// <summary>Creates a new API token.</summary>
    public async Task CreateApiTokenAsync(ApiToken token, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO ApiTokens (Id, Name, TokenHash, TokenPrefix, CreatedAt, LastUsedAt, ExpiresAt)
            VALUES (@Id, @Name, @TokenHash, @TokenPrefix, @CreatedAt, @LastUsedAt, @ExpiresAt);
            """,
            new
            {
                Id = token.Id.ToString().ToUpperInvariant(),
                token.Name,
                token.TokenHash,
                token.TokenPrefix,
                CreatedAt = token.CreatedAt.ToString("o"),
                LastUsedAt = token.LastUsedAt?.ToString("o"),
                ExpiresAt = token.ExpiresAt?.ToString("o"),
            });
    }

    /// <summary>Deletes an API token by id.</summary>
    public async Task<int> DeleteApiTokenAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        return await conn.ExecuteAsync("DELETE FROM ApiTokens WHERE Id = @id;", new { id = id.ToString().ToUpperInvariant() });
    }

    // ------------------------------------------------------------------
    // Franchises
    // ------------------------------------------------------------------

    /// <summary>Finds a franchise by name (case-insensitive).</summary>
    public async Task<Franchise?> GetFranchiseByNameAsync(string name, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Franchises WHERE LOWER(Name) = LOWER(@name);";
        cmd.Parameters.Add(new SqliteParameter("@name", name));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;

        return new Franchise
        {
            Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
            Name = reader.GetString(reader.GetOrdinal("Name")),
            Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
            CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
        };
    }

    /// <summary>Returns all franchises.</summary>
    public async Task<List<Franchise>> GetAllFranchisesAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Franchises ORDER BY Name;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<Franchise>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new Franchise
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
            });
        }
        return list;
    }

    /// <summary>Creates a new franchise.</summary>
    public async Task CreateFranchiseAsync(Franchise franchise, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO Franchises (Id, Name, Description, CoverUrl)
            VALUES (@Id, @Name, @Description, @CoverUrl);
            """,
            new
            {
                Id = franchise.Id.ToString().ToUpperInvariant(),
                franchise.Name,
                Description = (object?)franchise.Description ?? DBNull.Value,
                CoverUrl = (object?)franchise.CoverUrl ?? DBNull.Value,
            });
    }

    // ------------------------------------------------------------------
    // CustomLists / CustomListItems
    // ------------------------------------------------------------------

    /// <summary>Returns all custom lists with their items.</summary>
    public async Task<List<CustomList>> GetCustomListsAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM CustomLists ORDER BY UpdatedAt DESC;";
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var lists = new List<CustomList>();
        while (await reader.ReadAsync(ct))
        {
            lists.Add(new CustomList
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                Name = reader.GetString(reader.GetOrdinal("Name")),
                Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
                Icon = reader.IsDBNull(reader.GetOrdinal("Icon")) ? "list" : reader.GetString(reader.GetOrdinal("Icon")),
                Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                UpdatedAt = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                SmartQueryJson = reader.IsDBNull(reader.GetOrdinal("SmartQueryJson")) ? null : reader.GetString(reader.GetOrdinal("SmartQueryJson")),
                Items = [],
            });
        }
        return lists;
    }

    /// <summary>Returns a single custom list by id.</summary>
    public async Task<CustomList?> GetCustomListAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM CustomLists WHERE Id = @id;";
        cmd.Parameters.Add(new SqliteParameter("@id", id.ToString().ToUpperInvariant()));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;

        return new CustomList
        {
            Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
            Name = reader.GetString(reader.GetOrdinal("Name")),
            Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
            Icon = reader.IsDBNull(reader.GetOrdinal("Icon")) ? "list" : reader.GetString(reader.GetOrdinal("Icon")),
            Color = reader.IsDBNull(reader.GetOrdinal("Color")) ? null : reader.GetString(reader.GetOrdinal("Color")),
            CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
            UpdatedAt = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
            SmartQueryJson = reader.IsDBNull(reader.GetOrdinal("SmartQueryJson")) ? null : reader.GetString(reader.GetOrdinal("SmartQueryJson")),
            Items = [],
        };
    }

    /// <summary>Returns all items of a custom list ordered by Order.</summary>
    public async Task<List<CustomListItem>> GetCustomListItemsAsync(Guid listId, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM CustomListItems WHERE ListId = @listId ORDER BY [Order], AddedAt;";
        cmd.Parameters.Add(new SqliteParameter("@listId", listId.ToString().ToUpperInvariant()));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var list = new List<CustomListItem>();
        while (await reader.ReadAsync(ct))
        {
            list.Add(new CustomListItem
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                ListId = Guid.Parse(reader.GetString(reader.GetOrdinal("ListId"))),
                MediaItemId = Guid.Parse(reader.GetString(reader.GetOrdinal("MediaItemId"))),
                Order = reader.GetInt32(reader.GetOrdinal("Order")),
                AddedAt = reader.GetDateTime(reader.GetOrdinal("AddedAt")),
            });
        }
        return list;
    }

    /// <summary>Creates a new custom list.</summary>
    public async Task CreateCustomListAsync(CustomList list, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO CustomLists (Id, Name, Description, Icon, Color, CreatedAt, UpdatedAt, SmartQueryJson)
            VALUES (@Id, @Name, @Description, @Icon, @Color, @CreatedAt, @UpdatedAt, @SmartQueryJson);
            """,
            new
            {
                Id = list.Id.ToString().ToUpperInvariant(),
                list.Name,
                Description = (object?)list.Description ?? DBNull.Value,
                Icon = (object?)list.Icon ?? "list",
                Color = (object?)list.Color ?? DBNull.Value,
                CreatedAt = list.CreatedAt.ToString("o"),
                UpdatedAt = list.UpdatedAt.ToString("o"),
                SmartQueryJson = (object?)list.SmartQueryJson ?? DBNull.Value,
            });
    }

    /// <summary>Updates a custom list. Returns false if not found.</summary>
    public async Task<bool> UpdateCustomListAsync(CustomList list, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var result = await conn.ExecuteAsync(
            """
            UPDATE CustomLists SET Name = @Name, Description = @Description, Icon = @Icon, Color = @Color,
                UpdatedAt = @UpdatedAt, SmartQueryJson = @SmartQueryJson
            WHERE Id = @Id;
            """,
            new
            {
                Id = list.Id.ToString().ToUpperInvariant(),
                list.Name,
                Description = (object?)list.Description ?? DBNull.Value,
                Icon = (object?)list.Icon ?? "list",
                Color = (object?)list.Color ?? DBNull.Value,
                UpdatedAt = DateTime.UtcNow.ToString("o"),
                SmartQueryJson = (object?)list.SmartQueryJson ?? DBNull.Value,
            });
        return result > 0;
    }

    /// <summary>Deletes a custom list. Returns false if not found.</summary>
    public async Task<bool> DeleteCustomListAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var result = await conn.ExecuteAsync("DELETE FROM CustomLists WHERE Id = @id;", new { id = id.ToString().ToUpperInvariant() });
        return result > 0;
    }

    /// <summary>Inserts a custom list item with the entity's own Id, Order and AddedAt (no side effects).</summary>
    public async Task InsertCustomListItemAsync(CustomListItem item, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        await conn.ExecuteAsync(
            """
            INSERT INTO CustomListItems (Id, ListId, MediaItemId, [Order], AddedAt)
            VALUES (@Id, @ListId, @MediaItemId, @Order, @AddedAt);
            """,
            new
            {
                Id = item.Id.ToString().ToUpperInvariant(),
                ListId = item.ListId.ToString().ToUpperInvariant(),
                MediaItemId = item.MediaItemId.ToString().ToUpperInvariant(),
                item.Order,
                AddedAt = item.AddedAt.ToString("o"),
            });
    }

    /// <summary>Adds a media item to a custom list. Returns false if already present or list/media missing.</summary>
    public async Task<bool> AddCustomListItemAsync(Guid listId, Guid mediaId, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        // Check list exists
        var listExists = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM CustomLists WHERE Id = @listId;",
            new { listId = listId.ToString().ToUpperInvariant() }) > 0;
        if (!listExists) return false;

        // Check media exists
        var mediaExists = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM MediaItems WHERE Id = @mediaId;",
            new { mediaId = mediaId.ToString().ToUpperInvariant() }) > 0;
        if (!mediaExists) return false;

        // Check already present
        var alreadyPresent = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM CustomListItems WHERE ListId = @listId AND MediaItemId = @mediaId;",
            new { listId = listId.ToString().ToUpperInvariant(), mediaId = mediaId.ToString().ToUpperInvariant() }) > 0;
        if (alreadyPresent) return true;

        // Get next order
        var orderResult = await conn.ExecuteScalarAsync(
            "SELECT COALESCE(MAX([Order]), -1) FROM CustomListItems WHERE ListId = @listId;",
            new { listId = listId.ToString().ToUpperInvariant() });
        var order = orderResult is null or DBNull ? 0 : Convert.ToInt32(orderResult) + 1;

        await conn.ExecuteAsync(
            """
            INSERT INTO CustomListItems (Id, ListId, MediaItemId, [Order], AddedAt)
            VALUES (@Id, @ListId, @MediaItemId, @Order, @AddedAt);
            """,
            new
            {
                Id = Guid.NewGuid().ToString().ToUpperInvariant(),
                ListId = listId.ToString().ToUpperInvariant(),
                MediaItemId = mediaId.ToString().ToUpperInvariant(),
                Order = order,
                AddedAt = DateTime.UtcNow.ToString("o"),
            });

        // Update list UpdatedAt
        await conn.ExecuteAsync(
            "UPDATE CustomLists SET UpdatedAt = @updatedAt WHERE Id = @listId;",
            new { updatedAt = DateTime.UtcNow.ToString("o"), listId = listId.ToString().ToUpperInvariant() });

        return true;
    }

    /// <summary>Removes a media item from a custom list. Returns false if not present.</summary>
    public async Task<bool> RemoveCustomListItemAsync(Guid listId, Guid mediaId, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        var result = await conn.ExecuteAsync(
            "DELETE FROM CustomListItems WHERE ListId = @listId AND MediaItemId = @mediaId;",
            new { listId = listId.ToString().ToUpperInvariant(), mediaId = mediaId.ToString().ToUpperInvariant() });
        if (result > 0)
        {
            await conn.ExecuteAsync(
                "UPDATE CustomLists SET UpdatedAt = @updatedAt WHERE Id = @listId;",
                new { updatedAt = DateTime.UtcNow.ToString("o"), listId = listId.ToString().ToUpperInvariant() });
        }
        return result > 0;
    }

    /// <summary>Returns non-smart list ids containing the given media item.</summary>
    public async Task<List<Guid>> GetCustomListIdsForMediaAsync(Guid mediaId, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT DISTINCT cli.ListId
            FROM CustomListItems cli
            JOIN CustomLists cl ON cl.Id = cli.ListId
            WHERE cli.MediaItemId = @mediaId AND cl.SmartQueryJson IS NULL;
            """;
        cmd.Parameters.Add(new SqliteParameter("@mediaId", mediaId.ToString().ToUpperInvariant()));
        using var reader = await cmd.ExecuteReaderAsync(ct);
        var ids = new List<Guid>();
        while (await reader.ReadAsync(ct))
        {
            ids.Add(Guid.Parse(reader.GetString(0)));
        }
        return ids;
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// <summary>Returns media events, optionally filtered by media id and/or date.</summary>
    public async Task<List<MediaEvent>> GetMediaEventsAsync(
        Guid? mediaId = null, DateTime? start = null, DateTime? end = null, int limit = 500,
        CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        using var cmd = conn.CreateCommand();
        var sb = new System.Text.StringBuilder("SELECT * FROM Events WHERE 1=1");
        var paramIndex = 0;

        if (mediaId is { } mid)
        {
            sb.Append(" AND MediaId = @p").Append(paramIndex);
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", mid.ToString().ToUpperInvariant()));
            paramIndex++;
        }

        if (start is { } s)
        {
            sb.Append(" AND CreatedAt >= @p").Append(paramIndex);
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", s.ToString("o")));
            paramIndex++;
        }

        if (end is { } e)
        {
            sb.Append(" AND CreatedAt <= @p").Append(paramIndex);
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", e.ToString("o")));
            paramIndex++;
        }

        sb.Append(" ORDER BY CreatedAt DESC LIMIT @p").Append(paramIndex);
        cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", limit));
        cmd.CommandText = sb.ToString();

        using var reader = await cmd.ExecuteReaderAsync(ct);
        var events = new List<MediaEvent>();
        while (await reader.ReadAsync(ct))
        {
            events.Add(new MediaEvent
            {
                Id = Guid.Parse(reader.GetString(reader.GetOrdinal("Id"))),
                MediaId = Guid.Parse(reader.GetString(reader.GetOrdinal("MediaId"))),
                Type = (MediaEventType)reader.GetInt32(reader.GetOrdinal("Type")),
                OldValue = reader.IsDBNull(reader.GetOrdinal("OldValue")) ? null : reader.GetString(reader.GetOrdinal("OldValue")),
                NewValue = reader.IsDBNull(reader.GetOrdinal("NewValue")) ? null : reader.GetString(reader.GetOrdinal("NewValue")),
                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
            });
        }
        return events;
    }

    /// <summary>Deletes a single event by id. Returns rows affected.</summary>
    public async Task<int> DeleteMediaEventAsync(Guid id, CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        return await conn.ExecuteAsync("DELETE FROM Events WHERE Id = @id;", new { id = id.ToString().ToUpperInvariant() });
    }

    /// <summary>Deletes all events. Returns rows affected.</summary>
    public async Task<int> DeleteAllMediaEventsAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        return await conn.ExecuteAsync("DELETE FROM Events;");
    }

    /// <summary>Resets StartedAt and FinishedAt on all media items. Returns rows affected.</summary>
    public async Task<int> ResetMediaTimestampsAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await EnsureSchemaAsync(ct);

        return await conn.ExecuteAsync(
            "UPDATE MediaItems SET StartedAt = NULL, FinishedAt = NULL;");
    }

    // ------------------------------------------------------------------
    // Schema
    // ------------------------------------------------------------------

    internal async Task EnsureSchemaAsync(CancellationToken ct = default)
    {
        var conn = Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
        await SqliteSchemaInitializer.InitializeAsync(Connection, ct, foreignKeys: !_foreignKeysSuspended);
    }

    // ------------------------------------------------------------------
    // DbSet shim for EF Core compatibility in tests
    // ------------------------------------------------------------------

    /// <summary>Read-only DbSet shim backed by Dapper. All mutations go through the pending queue.</summary>
    public sealed class DbSetShim<T> : IEnumerable<T> where T : class
    {
        private readonly AppDbContext _db;
        private readonly Func<CancellationToken, Task<List<T>>> _loader;

        public DbSetShim(AppDbContext db, Func<CancellationToken, Task<List<T>>> loader)
        {
            _db = db;
            _loader = loader;
        }

        public IEnumerator<T> GetEnumerator()
        {
            return _loader(CancellationToken.None).GetAwaiter().GetResult().GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }

        public void Add(T entity) => _db.Add(entity);
        public void AddRange(IEnumerable<T> entities)
        {
            foreach (var e in entities) _db.Add(e);
        }
        public void AddRange(params T[] entities)
        {
            foreach (var e in entities) _db.Add(e);
        }
        public void Remove(T entity) => _db._pendingRemoves.Add(entity);
        public void RemoveRange(IEnumerable<T> entities)
        {
            foreach (var e in entities) _db._pendingRemoves.Add(e);
        }

        public Task<List<T>> ToListAsync(CancellationToken ct = default) => _loader(ct);
        public List<T> ToList() => _loader(CancellationToken.None).GetAwaiter().GetResult();

        public async Task<T?> FirstOrDefaultAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return predicate is null ? all.FirstOrDefault() : all.FirstOrDefault(predicate.Compile());
        }
        public T? FirstOrDefault(Expression<Func<T, bool>>? predicate = null)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return predicate is null ? all.FirstOrDefault() : all.FirstOrDefault(predicate.Compile());
        }

        public async Task<T?> SingleOrDefaultAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return predicate is null ? all.SingleOrDefault() : all.SingleOrDefault(predicate.Compile());
        }
        public T? SingleOrDefault(Expression<Func<T, bool>>? predicate = null)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return predicate is null ? all.SingleOrDefault() : all.SingleOrDefault(predicate.Compile());
        }

        public async Task<T> SingleAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return predicate is null ? all.Single() : all.Single(predicate.Compile());
        }
        public T Single(Expression<Func<T, bool>>? predicate = null)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return predicate is null ? all.Single() : all.Single(predicate.Compile());
        }

        [global::System.Diagnostics.CodeAnalysis.UnconditionalSuppressMessage(
            "Trimming", "IL2090", Justification = "Test-only EF shim; id property lookup never runs under AOT.")]
        public async Task<T?> FindAsync(object id, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            var idStr = id?.ToString();
            return all.FirstOrDefault(e =>
            {
                var prop = typeof(T).GetProperty("Id") ?? typeof(T).GetProperty("Key");
                if (prop == null) return false;
                var val = prop.GetValue(e);
                return val?.ToString() == idStr;
            });
        }
        public T? Find(Guid id)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return all.FirstOrDefault(e => GetId(e) == id);
        }

        public async Task<bool> AnyAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return predicate is null ? all.Any() : all.Any(predicate.Compile());
        }
        public bool Any(Expression<Func<T, bool>>? predicate = null)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return predicate is null ? all.Any() : all.Any(predicate.Compile());
        }

        public async Task<bool> AllAsync(Expression<Func<T, bool>> predicate, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return all.All(predicate.Compile());
        }
        public bool All(Expression<Func<T, bool>> predicate)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return all.All(predicate.Compile());
        }

        public async Task<int> CountAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default)
        {
            var all = await _loader(ct);
            return predicate is null ? all.Count : all.Count(predicate.Compile());
        }
        public int Count(Expression<Func<T, bool>>? predicate = null)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return predicate is null ? all.Count : all.Count(predicate.Compile());
        }

        public DbSetShim<T> Where(Expression<Func<T, bool>> predicate)
        {
            var all = _loader(CancellationToken.None).GetAwaiter().GetResult();
            return new DbSetShim<T>(_db, _ => Task.FromResult(all.Where(predicate.Compile()).ToList()));
        }

        public DbSetShim<T> AsNoTracking() => this;
        public DbSetShim<T> Include<TProperty>(Expression<Func<T, TProperty>>? navigationExpression = null) => this;

        [global::System.Diagnostics.CodeAnalysis.UnconditionalSuppressMessage(
            "Trimming", "IL2090", Justification = "Test-only EF shim; id property lookup never runs under AOT.")]
        private static Guid GetId(T entity)
        {
            var prop = typeof(T).GetProperty("Id") ?? typeof(T).GetProperty("Id")!;
            return (Guid)prop.GetValue(entity)!;
        }
    }

    /// <summary>Database facade shim for EF Core compatibility in tests.</summary>
    public sealed class DatabaseFacadeShim
    {
        private readonly AppDbContext _db;

        public DatabaseFacadeShim(AppDbContext db) => _db = db;

        private async Task InitializeAsync(CancellationToken ct)
        {
            var conn = _db.Connection;
            if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
            await _db.EnsureSchemaAsync(ct);
        }

        public void EnsureCreated() => InitializeAsync(CancellationToken.None).GetAwaiter().GetResult();
        public Task EnsureCreatedAsync(CancellationToken ct = default) => InitializeAsync(ct);
        public void Migrate() => InitializeAsync(CancellationToken.None).GetAwaiter().GetResult();
        public Task MigrateAsync(CancellationToken ct = default) => InitializeAsync(ct);

        public async Task<int> ExecuteSqlRawAsync(string sql, CancellationToken ct = default)
        {
            var conn = _db.Connection;
            if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
            using var cmd = conn.CreateCommand();
            cmd.CommandText = sql;
            return await cmd.ExecuteNonQueryAsync(ct);
        }

        public async Task<DbTransaction> BeginTransactionAsync(CancellationToken ct = default)
        {
            var conn = _db.Connection;
            if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);
            return await conn.BeginTransactionAsync(ct);
        }
    }

    /// <summary>Change tracker stub for EF Core compatibility in tests.</summary>
    /// <summary>Change tracker stub for EF Core compatibility in tests.</summary>
    public sealed class ChangeTrackerShim
    {
        private readonly AppDbContext _db;
        public ChangeTrackerShim(AppDbContext db) => _db = db;

        public IEnumerable<object> Entries<T>() where T : class => Enumerable.Empty<object>();

        public void Clear() { }

        public enum EntityState
        {
            Unchanged,
            Added,
            Deleted,
            Modified,
            Detached
        }
    }

    public ChangeTrackerShim ChangeTracker => new(this);
}
