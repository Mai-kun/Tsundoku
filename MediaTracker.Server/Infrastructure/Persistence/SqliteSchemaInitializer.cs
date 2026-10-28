using System.Data.Common;
using System.Threading;

namespace MediaTracker.Server.Infrastructure.Persistence;

/// <summary>
/// Initialises the SQLite schema using Dapper.AOT-compatible raw SQL. Mirrors the
/// <see cref="MediaTracker.Server.Migrations.InitialCreate"/> migration exactly so the Dapper
/// path can run without EF Core migrations. Idempotent: safe to run on every connection open.
/// </summary>
public static class SqliteSchemaInitializer
{
    private static int _journalModeApplied;

    /// <summary>
    /// Applies PRAGMA settings and creates all tables/indexes if they don't exist.
    /// <paramref name="connection"/> must already be open.
    /// </summary>
    public static async Task InitializeAsync(DbConnection connection, CancellationToken ct = default, bool foreignKeys = true)
    {
        // PRAGMA journal_mode = WAL is persistent, so only run once per process.
        // Other pragmas are per-connection and must be reapplied.
        var pragmaScript = Interlocked.Exchange(ref _journalModeApplied, 1) == 0
            ? "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000; PRAGMA cache_size = -64000; PRAGMA mmap_size = 268435456;"
            : "PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000; PRAGMA cache_size = -64000; PRAGMA mmap_size = 268435456;";

        // Foreign keys are per-connection. The EF-compatibility shim (SaveChangesAsync) suspends
        // them so test seeds may insert children before parents, matching Microsoft.Data.Sqlite's
        // default of FK enforcement off.
        pragmaScript += foreignKeys ? " PRAGMA foreign_keys = ON;" : " PRAGMA foreign_keys = OFF;";

        using var pragmaCmd = connection.CreateCommand();
        pragmaCmd.CommandText = pragmaScript;
        await pragmaCmd.ExecuteNonQueryAsync(ct);

        using var cmd = connection.CreateCommand();
        cmd.CommandText = SchemaSql;
        await cmd.ExecuteNonQueryAsync(ct);

        await MigrateAsync(connection, ct);
    }

    /// <summary>
    /// Column additions for databases created before the matching CREATE TABLE existed. CREATE TABLE
    /// IF NOT EXISTS cannot touch an already-materialised table, so each added column is checked for
    /// with PRAGMA table_info and appended with ALTER TABLE when missing.
    /// </summary>
    private static async Task MigrateAsync(DbConnection connection, CancellationToken ct)
    {
        var existingColumns = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var infoCmd = connection.CreateCommand())
        {
            infoCmd.CommandText = "PRAGMA table_info(MediaItems);";
            using var reader = await infoCmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                existingColumns.Add(reader.GetString(1));
            }
        }

        if (!existingColumns.Contains("CoversJson"))
        {
            using var alterCmd = connection.CreateCommand();
            alterCmd.CommandText = "ALTER TABLE MediaItems ADD COLUMN CoversJson TEXT NULL;";
            await alterCmd.ExecuteNonQueryAsync(ct);
        }
    }

    private const string SchemaSql = @"
CREATE TABLE IF NOT EXISTS ApiTokens (
    Id TEXT NOT NULL PRIMARY KEY,
    Name TEXT NOT NULL,
    TokenHash TEXT NOT NULL,
    TokenPrefix TEXT NOT NULL,
    CreatedAt TEXT NOT NULL,
    LastUsedAt TEXT,
    ExpiresAt TEXT
);

CREATE TABLE IF NOT EXISTS CustomLists (
    Id TEXT NOT NULL PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    Icon TEXT DEFAULT 'list',
    Color TEXT,
    CreatedAt TEXT NOT NULL,
    UpdatedAt TEXT NOT NULL,
    SmartQueryJson TEXT
);

CREATE TABLE IF NOT EXISTS Franchises (
    Id TEXT NOT NULL PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    CoverUrl TEXT
);

CREATE TABLE IF NOT EXISTS Settings (
    Key TEXT NOT NULL PRIMARY KEY,
    Value TEXT NOT NULL,
    UpdatedAt TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS MediaItems (
    Id TEXT NOT NULL PRIMARY KEY,
    Title TEXT NOT NULL,
    Status INTEGER NOT NULL,
    Score INTEGER,
    DetailedScoreJson TEXT,
    StartedAt TEXT,
    FinishedAt TEXT,
    LastActivityAt TEXT,
    Notes TEXT,
    DropReason TEXT,
    DropNotes TEXT,
    QuotesJson TEXT,
    Description TEXT,
    TrailerVideoId TEXT,
    CoverUrl TEXT,
    CoversJson TEXT NULL,
    CreatorImageUrl TEXT,
    SyncStatus INTEGER NOT NULL,
    CreatedAt TEXT NOT NULL,
    UpdatedAt TEXT NOT NULL,
    FranchiseId TEXT,
    FranchiseOrder INTEGER,
    ExternalId TEXT,
    ExternalSource TEXT,
    ImportSource TEXT,
    ExternalRating REAL,
    ExternalRatingVotes INTEGER,
    ExternalRatingsJson TEXT,
    NextAutoRefreshAt TEXT,
    AutoRefreshIntervalDays INTEGER NOT NULL,
    LastAutoRefreshedAt TEXT,
    ReleaseDate TEXT,
    ReleaseYear INTEGER,
    EndDate TEXT,
    WatchedOn TEXT,
    ReleaseStatus TEXT,
    OriginalLanguage TEXT,
    CountryOfOrigin TEXT,
    OriginalTitle TEXT,
    CastJson TEXT,
    StaffJson TEXT,
    TranslatedSynopsis TEXT,
    TranslationLanguage TEXT,
    Genres TEXT,
    Tags TEXT,
    UnlockedAchievements TEXT,
    UserPlatform TEXT,
    RelatedMediaJson TEXT,
    PendingMatchesJson TEXT,
    RelatedSource TEXT,
    AchievementsJson TEXT,
    RecommendationsJson TEXT,
    RecommendationsUpdatedAt TEXT,
    IsCustomEdited INTEGER NOT NULL,
    MediaType TEXT NOT NULL,
    Author TEXT,
    CurrentPage INTEGER,
    TotalPages INTEGER,
    CurrentChapter INTEGER,
    TotalChapters INTEGER,
    Manga_Author TEXT,
    Manga_RomajiTitle TEXT,
    Manga_Format TEXT,
    CurrentVolume INTEGER,
    Manga_TotalVolumes INTEGER,
    DurationMinutes INTEGER,
    Director TEXT,
    Movie_IsAnime INTEGER,
    Movie_Studio TEXT,
    Movie_RomajiTitle TEXT,
    Network TEXT,
    TvShow_IsAnime INTEGER,
    TvShow_Studio TEXT,
    TvShow_RomajiTitle TEXT,
    TvShow_EpisodeDurationMinutes INTEGER,
    Platform TEXT,
    HoursPlayed INTEGER,
    Studio TEXT,
    CONSTRAINT FK_MediaItems_Franchises_FranchiseId FOREIGN KEY (FranchiseId) REFERENCES Franchises (Id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS CustomListItems (
    Id TEXT NOT NULL PRIMARY KEY,
    ListId TEXT NOT NULL,
    MediaItemId TEXT NOT NULL,
    [Order] INTEGER NOT NULL,
    AddedAt TEXT NOT NULL,
    CONSTRAINT FK_CustomListItems_CustomLists_ListId FOREIGN KEY (ListId) REFERENCES CustomLists (Id) ON DELETE CASCADE,
    CONSTRAINT FK_CustomListItems_MediaItems_MediaItemId FOREIGN KEY (MediaItemId) REFERENCES MediaItems (Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Events (
    Id TEXT NOT NULL PRIMARY KEY,
    MediaId TEXT NOT NULL,
    Type INTEGER NOT NULL,
    OldValue TEXT,
    NewValue TEXT,
    CreatedAt TEXT NOT NULL,
    CONSTRAINT FK_Events_MediaItems_MediaId FOREIGN KEY (MediaId) REFERENCES MediaItems (Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS MangaVolumes (
    Id TEXT NOT NULL PRIMARY KEY,
    VolumeNumber INTEGER NOT NULL,
    Title TEXT NOT NULL,
    CoverUrl TEXT,
    CurrentPage INTEGER NOT NULL,
    TotalPages INTEGER NOT NULL,
    CurrentChapter INTEGER NOT NULL,
    TotalChapters INTEGER NOT NULL,
    Status INTEGER NOT NULL,
    Score INTEGER,
    Notes TEXT,
    ReleaseDate TEXT,
    MangaId TEXT NOT NULL,
    CONSTRAINT FK_MangaVolumes_MediaItems_MangaId FOREIGN KEY (MangaId) REFERENCES MediaItems (Id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS TvSeasons (
    Id TEXT NOT NULL PRIMARY KEY,
    SeasonNumber INTEGER NOT NULL,
    Title TEXT NOT NULL,
    CoverUrl TEXT,
    CurrentEpisode INTEGER NOT NULL,
    TotalEpisodes INTEGER NOT NULL,
    Status INTEGER NOT NULL,
    Score INTEGER,
    Notes TEXT,
    AirDate TEXT,
    EpisodesData TEXT,
    TvShowId TEXT NOT NULL,
    CONSTRAINT FK_TvSeasons_MediaItems_TvShowId FOREIGN KEY (TvShowId) REFERENCES MediaItems (Id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS IX_ApiTokens_TokenHash ON ApiTokens (TokenHash);
CREATE INDEX IF NOT EXISTS IX_CustomListItems_ListId_MediaItemId ON CustomListItems (ListId, MediaItemId);
CREATE INDEX IF NOT EXISTS IX_CustomListItems_MediaItemId ON CustomListItems (MediaItemId);
CREATE INDEX IF NOT EXISTS IX_Events_CreatedAt ON Events (CreatedAt);
CREATE INDEX IF NOT EXISTS IX_Events_MediaId ON Events (MediaId);
CREATE INDEX IF NOT EXISTS IX_MangaVolumes_MangaId ON MangaVolumes (MangaId);
CREATE INDEX IF NOT EXISTS IX_MangaVolumes_MangaId_VolumeNumber ON MangaVolumes (MangaId, VolumeNumber);
CREATE INDEX IF NOT EXISTS IX_MediaItems_CreatedAt ON MediaItems (CreatedAt);
CREATE INDEX IF NOT EXISTS IX_MediaItems_FranchiseId ON MediaItems (FranchiseId);
CREATE INDEX IF NOT EXISTS IX_MediaItems_MediaType ON MediaItems (MediaType);
CREATE INDEX IF NOT EXISTS IX_MediaItems_MediaType_Status_CreatedAt ON MediaItems (MediaType, Status, CreatedAt);
CREATE INDEX IF NOT EXISTS IX_MediaItems_Movie_IsAnime ON MediaItems (Movie_IsAnime);
CREATE INDEX IF NOT EXISTS IX_MediaItems_NextAutoRefreshAt ON MediaItems (NextAutoRefreshAt);
CREATE INDEX IF NOT EXISTS IX_MediaItems_Status ON MediaItems (Status);
CREATE INDEX IF NOT EXISTS IX_MediaItems_Status_CreatedAt ON MediaItems (Status, CreatedAt);
CREATE INDEX IF NOT EXISTS IX_MediaItems_TvShow_IsAnime ON MediaItems (TvShow_IsAnime);
CREATE INDEX IF NOT EXISTS IX_TvSeasons_TvShowId ON TvSeasons (TvShowId);
CREATE INDEX IF NOT EXISTS IX_TvSeasons_TvShowId_SeasonNumber ON TvSeasons (TvShowId, SeasonNumber);
";

    /// <summary>Name of the type-discriminator column used for TPH.</summary>
    public const string DiscriminatorColumn = "MediaType";

    /// <summary>Discriminator values written into MediaType for each TPH subtype.</summary>
    public static class MediaTypes
    {
        public const string Game = "Game";
        public const string Book = "Book";
        public const string Manga = "Manga";
        public const string Movie = "Movie";
        public const string TvShow = "TvShow";
    }
}
