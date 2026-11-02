using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Offline;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

public sealed class OfflineAnimeTests
{
    [Fact]
    public async Task Importer_And_Provider_Work_EndToEnd()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_offline_test_" + Path.GetRandomFileName());
        Directory.CreateDirectory(tempDir);

        try
        {
            var jsonlPath = Path.Combine(tempDir, "anime-offline-database.jsonl");
            var dbPath = Path.Combine(tempDir, "anime_offline.db");

            // Write 2 test JSONL entries
            var entry1 = new
            {
                sources = new[]
                {
                    "https://anilist.co/anime/1",
                    "https://myanimelist.net/anime/1",
                    "https://kitsu.app/anime/1",
                    "https://anidb.net/anime/1"
                },
                title = "Cowboy Bebop",
                type = "TV",
                episodes = 26,
                status = "FINISHED",
                animeSeason = new { season = "SPRING", year = 1998 },
                picture = "https://example.com/bebop.jpg",
                synonyms = new[] { "Кавбой Бибоп", "Ковбой Бибоп" },
                tags = new[] { "space", "action" }
            };

            var entry2 = new
            {
                sources = new[]
                {
                    "https://anilist.co/anime/56355",
                    "https://myanimelist.net/anime/56355"
                },
                title = "Sousou no Frieren",
                type = "TV",
                episodes = 28,
                status = "FINISHED",
                animeSeason = new { season = "FALL", year = 2023 },
                picture = "https://example.com/frieren.jpg",
                synonyms = new[] { "Frieren: Beyond Journey's End" },
                tags = new[] { "fantasy", "adventure" }
            };

            await File.WriteAllLinesAsync(jsonlPath, new[]
            {
                JsonSerializer.Serialize(entry1),
                JsonSerializer.Serialize(entry2)
            });

            // 1. Verify provider before DB creation returns empty (no crash, 100% silent)
            var appPaths = new AppPaths(tempDir, isDevelopment: true);
            var provider = new UniversalOfflineMetadataProvider(appPaths: appPaths, logger: NullLogger<UniversalOfflineMetadataProvider>.Instance);

            Assert.False(provider.IsDatabaseAvailable);
            var emptySearch = await provider.SearchAsync("Cowboy", CancellationToken.None);
            Assert.Empty(emptySearch);

            // 2. Import dump
            var importer = new AnimeOfflineDatabaseImporter();
            var count = await importer.ImportDumpAsync(jsonlPath, dbPath, (IProgress<AnimeOfflineDatabaseImporter.ImportProgress>?)null, ct: CancellationToken.None);
            Assert.Equal(2, count);
            Assert.True(File.Exists(dbPath));

            // 3. Verify provider after import
            var targetOfflineDir = Path.Combine(tempDir, "offline");
            Directory.CreateDirectory(targetOfflineDir);
            File.Copy(dbPath, Path.Combine(targetOfflineDir, "anime_offline.db"), overwrite: true);

            var activeProvider = new UniversalOfflineMetadataProvider(appPaths: appPaths, logger: NullLogger<UniversalOfflineMetadataProvider>.Instance);
            Assert.True(activeProvider.IsDatabaseAvailable);

            // Search by main title
            var resultsTitle = await activeProvider.SearchAsync("Bebop", CancellationToken.None);
            Assert.Single(resultsTitle);
            var bebop = resultsTitle[0];
            Assert.Equal("Cowboy Bebop", bebop.Title);
            Assert.Equal("1", bebop.AnilistId);
            Assert.Equal("1", bebop.MalId);
            Assert.Equal("1", bebop.KitsuId);
            Assert.Equal("1", bebop.AnidbId);
            Assert.Equal(26, bebop.TotalCount);
            Assert.Equal(1998, bebop.ReleaseYear);
            Assert.Equal("Completed", bebop.ReleaseStatus);

            // Search by synonym
            var resultsSynonym = await activeProvider.SearchAsync("Бибоп", CancellationToken.None);
            Assert.Single(resultsSynonym);
            Assert.Equal("Cowboy Bebop", resultsSynonym[0].Title);

            // Search by external ID (exact)
            var resultsId = await activeProvider.SearchAsync("56355", CancellationToken.None);
            Assert.Single(resultsId);
            Assert.Equal("Sousou no Frieren", resultsId[0].Title);

            // GetDetailsAsync by externalId
            var details = await activeProvider.GetDetailsAsync("56355", "Sousou no Frieren", CancellationToken.None);
            Assert.NotNull(details);
            Assert.Equal("Sousou no Frieren", details!.Title);
            Assert.Equal("56355", details.AnilistId);
            Assert.Equal("56355", details.MalId);

            // TestConnectionAsync
            var testConn = await activeProvider.TestConnectionAsync(CancellationToken.None);
            Assert.True(testConn.Success);
            Assert.Contains("2", testConn.Message);
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task ImdbBasicsImporter_And_OpenVgdbImporter_Work_EndToEnd()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_offline_all_test_" + Path.GetRandomFileName());
        Directory.CreateDirectory(tempDir);

        try
        {
            var appPaths = new AppPaths(tempDir, isDevelopment: true);
            var offlineDir = Path.Combine(tempDir, "offline");
            Directory.CreateDirectory(offlineDir);

            // 1. Create mock title.basics.tsv
            var tsvPath = Path.Combine(tempDir, "title.basics.tsv");
            var tsvLines = new[]
            {
                "tconst\ttitleType\tprimaryTitle\toriginalTitle\tisAdult\tstartYear\tendYear\truntimeMinutes\tgenres",
                "tt0000001\tshort\tCarmencita\tCarmencita\t0\t1894\t\\N\t1\tDocumentary,Short", // should be ignored (short)
                "tt0000002\tmovie\tAdult Movie\tAdult Movie\t1\t2000\t\\N\t90\tAdult", // should be ignored (isAdult=1)
                "tt0111161\tmovie\tThe Shawshank Redemption\tThe Shawshank Redemption\t0\t1994\t\\N\t142\tDrama",
                "tt0903747\ttvSeries\tBreaking Bad\tBreaking Bad\t0\t2008\t2013\t49\tCrime,Drama,Thriller"
            };
            await File.WriteAllLinesAsync(tsvPath, tsvLines);

            var imdbImporter = new ImdbBasicsImporter();
            var moviesDbPath = Path.Combine(offlineDir, "movies_offline.db");
            var imdbCount = await imdbImporter.ImportDumpAsync(tsvPath, moviesDbPath, ct: CancellationToken.None);
            Assert.Equal(2, imdbCount);

            // 2. Create mock openvgdb sqlite DB
            var openvgdbDir = Path.Combine(tempDir, "openvgdb");
            Directory.CreateDirectory(openvgdbDir);
            var mockVgdbPath = Path.Combine(openvgdbDir, "openvgdb.sqlite");

            await using (var vgConn = new SqliteConnection($"Data Source={mockVgdbPath};"))
            {
                await vgConn.OpenAsync();
                await using var createCmd = vgConn.CreateCommand();
                createCmd.CommandText = @"
                    CREATE TABLE RELEASES (
                        releaseID INTEGER PRIMARY KEY,
                        romID INTEGER,
                        releaseTitleName TEXT,
                        TEMPsystemName TEXT,
                        TEMPsystemShortName TEXT,
                        releaseCoverFront TEXT,
                        releaseDescription TEXT,
                        releaseDeveloper TEXT,
                        releasePublisher TEXT,
                        releaseGenre TEXT,
                        releaseDate TEXT
                    );
                    INSERT INTO RELEASES (releaseID, romID, releaseTitleName, TEMPsystemName, TEMPsystemShortName, releaseDate, releaseDeveloper, releaseGenre)
                    VALUES (101, 1, 'Chrono Trigger', 'Super Nintendo', 'SNES', '1995', 'Square', 'RPG');
                ";
                await createCmd.ExecuteNonQueryAsync();
            }

            var vgdbImporter = new OpenVgdbImporter();
            var gamesDbPath = Path.Combine(offlineDir, "games_offline.db");
            var gamesCount = await vgdbImporter.ImportAsync(openvgdbDir, gamesDbPath, ct: CancellationToken.None);
            Assert.Equal(1, gamesCount);

            // 3. Universal Provider searches
            var provider = new UniversalOfflineMetadataProvider(appPaths: appPaths, logger: NullLogger<UniversalOfflineMetadataProvider>.Instance);
            Assert.True(provider.IsDatabaseAvailable);

            // Search movie
            var movieResults = await provider.SearchAsync("Shawshank", "movie", CancellationToken.None);
            Assert.Single(movieResults);
            Assert.Equal("The Shawshank Redemption", movieResults[0].Title);
            Assert.Equal("movie", movieResults[0].Type);
            Assert.Equal(1994, movieResults[0].ReleaseYear);

            // Search tvshow
            var tvResults = await provider.SearchAsync("Breaking Bad", "tvshow", CancellationToken.None);
            Assert.Single(tvResults);
            Assert.Equal("Breaking Bad", tvResults[0].Title);
            Assert.Equal("tvshow", tvResults[0].Type);

            // Search game
            var gameResults = await provider.SearchAsync("Chrono Trigger", "game", CancellationToken.None);
            Assert.Single(gameResults);
            Assert.Equal("Chrono Trigger", gameResults[0].Title);
            Assert.Equal("game", gameResults[0].Type);
            Assert.Equal(1995, gameResults[0].ReleaseYear);

            // Test connection across both DBs
            var testConn = await provider.TestConnectionAsync(CancellationToken.None);
            Assert.True(testConn.Success);
            Assert.Contains("3", testConn.Message);
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }
}
