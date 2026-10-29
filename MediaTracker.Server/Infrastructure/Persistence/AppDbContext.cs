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

    internal static MediaItemRow ReadMediaItemRow(DbDataReader reader)
    {
        return new MediaItemRow
        {
            Id = reader.GetString(reader.GetOrdinal("Id")),
            Title = reader.GetString(reader.GetOrdinal("Title")),
            Status = reader.GetInt32(reader.GetOrdinal("Status")),
            Score = reader.IsDBNull(reader.GetOrdinal("Score")) ? null : reader.GetInt32(reader.GetOrdinal("Score")),
            DetailedScoreJson = reader.IsDBNull(reader.GetOrdinal("DetailedScoreJson")) ? null : reader.GetString(reader.GetOrdinal("DetailedScoreJson")),
            StartedAt = ReadNullableDateTime(reader, "StartedAt"),
            FinishedAt = ReadNullableDateTime(reader, "FinishedAt"),
            LastActivityAt = ReadNullableDateTime(reader, "LastActivityAt"),
            Notes = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
            DropReason = reader.IsDBNull(reader.GetOrdinal("DropReason")) ? null : reader.GetString(reader.GetOrdinal("DropReason")),
            DropNotes = reader.IsDBNull(reader.GetOrdinal("DropNotes")) ? null : reader.GetString(reader.GetOrdinal("DropNotes")),
            QuotesJson = reader.IsDBNull(reader.GetOrdinal("QuotesJson")) ? null : reader.GetString(reader.GetOrdinal("QuotesJson")),
            Description = reader.IsDBNull(reader.GetOrdinal("Description")) ? null : reader.GetString(reader.GetOrdinal("Description")),
            TrailerVideoId = reader.IsDBNull(reader.GetOrdinal("TrailerVideoId")) ? null : reader.GetString(reader.GetOrdinal("TrailerVideoId")),
            CoverUrl = reader.IsDBNull(reader.GetOrdinal("CoverUrl")) ? null : reader.GetString(reader.GetOrdinal("CoverUrl")),
            CoversJson = reader.IsDBNull(reader.GetOrdinal("CoversJson")) ? null : reader.GetString(reader.GetOrdinal("CoversJson")),
            CreatorImageUrl = reader.IsDBNull(reader.GetOrdinal("CreatorImageUrl")) ? null : reader.GetString(reader.GetOrdinal("CreatorImageUrl")),
            SyncStatus = (SyncStatus)reader.GetInt32(reader.GetOrdinal("SyncStatus")),
            CreatedAt = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
            UpdatedAt = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
            FranchiseId = reader.IsDBNull(reader.GetOrdinal("FranchiseId")) ? null : reader.GetString(reader.GetOrdinal("FranchiseId")),
            FranchiseOrder = reader.IsDBNull(reader.GetOrdinal("FranchiseOrder")) ? null : reader.GetInt32(reader.GetOrdinal("FranchiseOrder")),
            ExternalId = reader.IsDBNull(reader.GetOrdinal("ExternalId")) ? null : reader.GetString(reader.GetOrdinal("ExternalId")),
            ExternalSource = reader.IsDBNull(reader.GetOrdinal("ExternalSource")) ? null : reader.GetString(reader.GetOrdinal("ExternalSource")),
            ImportSource = reader.IsDBNull(reader.GetOrdinal("ImportSource")) ? null : reader.GetString(reader.GetOrdinal("ImportSource")),
            ExternalRating = reader.IsDBNull(reader.GetOrdinal("ExternalRating")) ? null : reader.GetDouble(reader.GetOrdinal("ExternalRating")),
            ExternalRatingVotes = reader.IsDBNull(reader.GetOrdinal("ExternalRatingVotes")) ? null : reader.GetInt32(reader.GetOrdinal("ExternalRatingVotes")),
            ExternalRatingsJson = reader.IsDBNull(reader.GetOrdinal("ExternalRatingsJson")) ? null : reader.GetString(reader.GetOrdinal("ExternalRatingsJson")),
            NextAutoRefreshAt = ReadNullableDateTime(reader, "NextAutoRefreshAt"),
            AutoRefreshIntervalDays = reader.GetInt32(reader.GetOrdinal("AutoRefreshIntervalDays")),
            LastAutoRefreshedAt = ReadNullableDateTime(reader, "LastAutoRefreshedAt"),
            ReleaseDate = ReadNullableDateTime(reader, "ReleaseDate"),
            ReleaseYear = reader.IsDBNull(reader.GetOrdinal("ReleaseYear")) ? null : reader.GetInt32(reader.GetOrdinal("ReleaseYear")),
            EndDate = ReadNullableDateTime(reader, "EndDate"),
            WatchedOn = reader.IsDBNull(reader.GetOrdinal("WatchedOn")) ? null : reader.GetString(reader.GetOrdinal("WatchedOn")),
            ReleaseStatus = reader.IsDBNull(reader.GetOrdinal("ReleaseStatus")) ? null : reader.GetString(reader.GetOrdinal("ReleaseStatus")),
            OriginalLanguage = reader.IsDBNull(reader.GetOrdinal("OriginalLanguage")) ? null : reader.GetString(reader.GetOrdinal("OriginalLanguage")),
            CountryOfOrigin = reader.IsDBNull(reader.GetOrdinal("CountryOfOrigin")) ? null : reader.GetString(reader.GetOrdinal("CountryOfOrigin")),
            OriginalTitle = reader.IsDBNull(reader.GetOrdinal("OriginalTitle")) ? null : reader.GetString(reader.GetOrdinal("OriginalTitle")),
            CastJson = reader.IsDBNull(reader.GetOrdinal("CastJson")) ? null : reader.GetString(reader.GetOrdinal("CastJson")),
            StaffJson = reader.IsDBNull(reader.GetOrdinal("StaffJson")) ? null : reader.GetString(reader.GetOrdinal("StaffJson")),
            TranslatedSynopsis = reader.IsDBNull(reader.GetOrdinal("TranslatedSynopsis")) ? null : reader.GetString(reader.GetOrdinal("TranslatedSynopsis")),
            TranslationLanguage = reader.IsDBNull(reader.GetOrdinal("TranslationLanguage")) ? null : reader.GetString(reader.GetOrdinal("TranslationLanguage")),
            Genres = reader.IsDBNull(reader.GetOrdinal("Genres")) ? null : reader.GetString(reader.GetOrdinal("Genres")),
            Tags = reader.IsDBNull(reader.GetOrdinal("Tags")) ? null : reader.GetString(reader.GetOrdinal("Tags")),
            UnlockedAchievements = reader.IsDBNull(reader.GetOrdinal("UnlockedAchievements")) ? null : reader.GetString(reader.GetOrdinal("UnlockedAchievements")),
            UserPlatform = reader.IsDBNull(reader.GetOrdinal("UserPlatform")) ? null : reader.GetString(reader.GetOrdinal("UserPlatform")),
            RelatedMediaJson = reader.IsDBNull(reader.GetOrdinal("RelatedMediaJson")) ? null : reader.GetString(reader.GetOrdinal("RelatedMediaJson")),
            PendingMatchesJson = reader.IsDBNull(reader.GetOrdinal("PendingMatchesJson")) ? null : reader.GetString(reader.GetOrdinal("PendingMatchesJson")),
            RelatedSource = reader.IsDBNull(reader.GetOrdinal("RelatedSource")) ? null : reader.GetString(reader.GetOrdinal("RelatedSource")),
            AchievementsJson = reader.IsDBNull(reader.GetOrdinal("AchievementsJson")) ? null : reader.GetString(reader.GetOrdinal("AchievementsJson")),
            RecommendationsJson = reader.IsDBNull(reader.GetOrdinal("RecommendationsJson")) ? null : reader.GetString(reader.GetOrdinal("RecommendationsJson")),
            RecommendationsUpdatedAt = ReadNullableDateTime(reader, "RecommendationsUpdatedAt"),
            IsCustomEdited = reader.GetBoolean(reader.GetOrdinal("IsCustomEdited")),
            MediaType = reader.GetString(reader.GetOrdinal("MediaType")),
            Author = reader.GetString(reader.GetOrdinal("MediaType")) == SqliteSchemaInitializer.MediaTypes.Manga
                ? (reader.IsDBNull(reader.GetOrdinal("Manga_Author"))
                    ? (reader.IsDBNull(reader.GetOrdinal("Author")) ? null : reader.GetString(reader.GetOrdinal("Author")))
                    : reader.GetString(reader.GetOrdinal("Manga_Author")))
                : (reader.IsDBNull(reader.GetOrdinal("Author")) ? null : reader.GetString(reader.GetOrdinal("Author"))),
            CurrentPage = reader.IsDBNull(reader.GetOrdinal("CurrentPage")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentPage")),
            TotalPages = reader.IsDBNull(reader.GetOrdinal("TotalPages")) ? null : reader.GetInt32(reader.GetOrdinal("TotalPages")),
            CurrentChapter = reader.IsDBNull(reader.GetOrdinal("CurrentChapter")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentChapter")),
            TotalChapters = reader.IsDBNull(reader.GetOrdinal("TotalChapters")) ? null : reader.GetInt32(reader.GetOrdinal("TotalChapters")),
            Manga_Author = reader.IsDBNull(reader.GetOrdinal("Manga_Author")) ? null : reader.GetString(reader.GetOrdinal("Manga_Author")),
            Manga_RomajiTitle = reader.IsDBNull(reader.GetOrdinal("Manga_RomajiTitle")) ? null : reader.GetString(reader.GetOrdinal("Manga_RomajiTitle")),
            Manga_Format = reader.IsDBNull(reader.GetOrdinal("Manga_Format")) ? null : reader.GetString(reader.GetOrdinal("Manga_Format")),
            CurrentVolume = reader.IsDBNull(reader.GetOrdinal("CurrentVolume")) ? null : reader.GetInt32(reader.GetOrdinal("CurrentVolume")),
            Manga_TotalVolumes = reader.IsDBNull(reader.GetOrdinal("Manga_TotalVolumes")) ? null : reader.GetInt32(reader.GetOrdinal("Manga_TotalVolumes")),
            DurationMinutes = reader.IsDBNull(reader.GetOrdinal("DurationMinutes")) ? null : reader.GetInt32(reader.GetOrdinal("DurationMinutes")),
            Director = reader.IsDBNull(reader.GetOrdinal("Director")) ? null : reader.GetString(reader.GetOrdinal("Director")),
            Movie_IsAnime = reader.IsDBNull(reader.GetOrdinal("Movie_IsAnime")) ? null : reader.GetBoolean(reader.GetOrdinal("Movie_IsAnime")),
            Movie_Studio = reader.IsDBNull(reader.GetOrdinal("Movie_Studio")) ? null : reader.GetString(reader.GetOrdinal("Movie_Studio")),
            Movie_RomajiTitle = reader.IsDBNull(reader.GetOrdinal("Movie_RomajiTitle")) ? null : reader.GetString(reader.GetOrdinal("Movie_RomajiTitle")),
            Network = reader.IsDBNull(reader.GetOrdinal("Network")) ? null : reader.GetString(reader.GetOrdinal("Network")),
            TvShow_IsAnime = reader.IsDBNull(reader.GetOrdinal("TvShow_IsAnime")) ? null : reader.GetBoolean(reader.GetOrdinal("TvShow_IsAnime")),
            TvShow_Studio = reader.IsDBNull(reader.GetOrdinal("TvShow_Studio")) ? null : reader.GetString(reader.GetOrdinal("TvShow_Studio")),
            TvShow_RomajiTitle = reader.IsDBNull(reader.GetOrdinal("TvShow_RomajiTitle")) ? null : reader.GetString(reader.GetOrdinal("TvShow_RomajiTitle")),
            TvShow_EpisodeDurationMinutes = reader.IsDBNull(reader.GetOrdinal("TvShow_EpisodeDurationMinutes")) ? null : reader.GetInt32(reader.GetOrdinal("TvShow_EpisodeDurationMinutes")),
            Platform = reader.IsDBNull(reader.GetOrdinal("Platform")) ? null : reader.GetString(reader.GetOrdinal("Platform")),
            HoursPlayed = reader.IsDBNull(reader.GetOrdinal("HoursPlayed")) ? null : reader.GetInt32(reader.GetOrdinal("HoursPlayed")),
            Studio = reader.IsDBNull(reader.GetOrdinal("Studio")) ? null : reader.GetString(reader.GetOrdinal("Studio")),
        };
    }

    private static DateTime? ReadNullableDateTime(DbDataReader reader, string columnName)
    {
        var ordinal = reader.GetOrdinal(columnName);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

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
            sb.Append(" AND ((m.MediaType = 'Movie' AND m.Movie_IsAnime = @p").Append(paramIndex);
            sb.Append(") OR (m.MediaType = 'TvShow' AND m.TvShow_IsAnime = @p").Append(paramIndex + 1).Append("))");
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex}", anime ? 1 : 0));
            cmd.Parameters.Add(new SqliteParameter($"@p{paramIndex + 1}", anime ? 1 : 0));
            paramIndex += 2;
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
        while (await reader.ReadAsync(ct))
        {
            rows.Add(ReadMediaItemRow(reader));
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

        // Load seasons for TvShow rows.
        var tvShowIds = rows.Where(r => r.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow).Select(r => r.Id.ToUpperInvariant()).Distinct().ToList();
        var seasonsByShow = new Dictionary<string, List<TvSeason>>(StringComparer.OrdinalIgnoreCase);
        if (tvShowIds.Count > 0)
        {
            var seasCmd = conn.CreateCommand();
            seasCmd.CommandText = $"SELECT * FROM TvSeasons WHERE TvShowId IN ({string.Join(",", tvShowIds.Select((_, i) => $"@sid{i}"))}) ORDER BY TvShowId, SeasonNumber";
            for (var i = 0; i < tvShowIds.Count; i++)
                seasCmd.Parameters.Add(new SqliteParameter($"@sid{i}", tvShowIds[i]));
            using var seasReader = await seasCmd.ExecuteReaderAsync(ct);
            while (await seasReader.ReadAsync(ct))
            {
                var key = seasReader.GetString(seasReader.GetOrdinal("TvShowId")).ToUpperInvariant();
                if (!seasonsByShow.TryGetValue(key, out var list))
                {
                    list = new List<TvSeason>();
                    seasonsByShow[key] = list;
                }
                list.Add(new TvSeason
                {
                    Id = Guid.Parse(seasReader.GetString(seasReader.GetOrdinal("Id"))),
                    SeasonNumber = seasReader.GetInt32(seasReader.GetOrdinal("SeasonNumber")),
                    Title = seasReader.GetString(seasReader.GetOrdinal("Title")),
                    CoverUrl = seasReader.IsDBNull(seasReader.GetOrdinal("CoverUrl")) ? null : seasReader.GetString(seasReader.GetOrdinal("CoverUrl")),
                    CurrentEpisode = seasReader.GetInt32(seasReader.GetOrdinal("CurrentEpisode")),
                    TotalEpisodes = seasReader.GetInt32(seasReader.GetOrdinal("TotalEpisodes")),
                    Status = (MediaStatus)seasReader.GetInt32(seasReader.GetOrdinal("Status")),
                    Score = seasReader.IsDBNull(seasReader.GetOrdinal("Score")) ? null : seasReader.GetInt32(seasReader.GetOrdinal("Score")),
                    Notes = seasReader.IsDBNull(seasReader.GetOrdinal("Notes")) ? null : seasReader.GetString(seasReader.GetOrdinal("Notes")),
                    AirDate = ReadNullableDateTime(seasReader, "AirDate"),
                    EpisodesData = seasReader.IsDBNull(seasReader.GetOrdinal("EpisodesData")) ? null : seasReader.GetString(seasReader.GetOrdinal("EpisodesData")),
                    TvShowId = Guid.Parse(seasReader.GetString(seasReader.GetOrdinal("TvShowId"))),
                });
            }
        }

        // Load volumes for Manga rows.
        var mangaIds = rows.Where(r => r.MediaType == SqliteSchemaInitializer.MediaTypes.Manga).Select(r => r.Id.ToUpperInvariant()).Distinct().ToList();
        var volumesByManga = new Dictionary<string, List<MangaVolume>>(StringComparer.OrdinalIgnoreCase);
        if (mangaIds.Count > 0)
        {
            var volCmd = conn.CreateCommand();
            volCmd.CommandText = $"SELECT * FROM MangaVolumes WHERE MangaId IN ({string.Join(",", mangaIds.Select((_, i) => $"@vid{i}"))}) ORDER BY MangaId, VolumeNumber";
            for (var i = 0; i < mangaIds.Count; i++)
                volCmd.Parameters.Add(new SqliteParameter($"@vid{i}", mangaIds[i]));
            using var volReader = await volCmd.ExecuteReaderAsync(ct);
            while (await volReader.ReadAsync(ct))
            {
                var key = volReader.GetString(volReader.GetOrdinal("MangaId")).ToUpperInvariant();
                if (!volumesByManga.TryGetValue(key, out var list))
                {
                    list = new List<MangaVolume>();
                    volumesByManga[key] = list;
                }
                list.Add(new MangaVolume
                {
                    Id = Guid.Parse(volReader.GetString(volReader.GetOrdinal("Id"))),
                    VolumeNumber = volReader.GetInt32(volReader.GetOrdinal("VolumeNumber")),
                    Title = volReader.GetString(volReader.GetOrdinal("Title")),
                    CoverUrl = volReader.IsDBNull(volReader.GetOrdinal("CoverUrl")) ? null : volReader.GetString(volReader.GetOrdinal("CoverUrl")),
                    CurrentPage = volReader.GetInt32(volReader.GetOrdinal("CurrentPage")),
                    TotalPages = volReader.GetInt32(volReader.GetOrdinal("TotalPages")),
                    CurrentChapter = volReader.GetInt32(volReader.GetOrdinal("CurrentChapter")),
                    TotalChapters = volReader.GetInt32(volReader.GetOrdinal("TotalChapters")),
                    Status = (MediaStatus)volReader.GetInt32(volReader.GetOrdinal("Status")),
                    Score = volReader.IsDBNull(volReader.GetOrdinal("Score")) ? null : volReader.GetInt32(volReader.GetOrdinal("Score")),
                    Notes = volReader.IsDBNull(volReader.GetOrdinal("Notes")) ? null : volReader.GetString(volReader.GetOrdinal("Notes")),
                    ReleaseDate = ReadNullableDateTime(volReader, "ReleaseDate"),
                    MangaId = Guid.Parse(volReader.GetString(volReader.GetOrdinal("MangaId"))),
                });
            }
        }

        var items = new List<MediaItem>(rows.Count);
        foreach (var row in rows)
        {
            var itemKey = row.Id.ToUpperInvariant();
            var franchise = row.FranchiseId != null && franchises.TryGetValue(row.FranchiseId.ToUpperInvariant(), out var f) ? f : null;
            var seasons = row.MediaType == SqliteSchemaInitializer.MediaTypes.TvShow && seasonsByShow.TryGetValue(itemKey, out var seasList) ? seasList : null;
            var volumes = row.MediaType == SqliteSchemaInitializer.MediaTypes.Manga && volumesByManga.TryGetValue(itemKey, out var v) ? v : null;
            items.Add(row.ToEntity(franchise, seasons, volumes));
        }

        return items;
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
