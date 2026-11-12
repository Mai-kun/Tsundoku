using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.Import.Parsers;
using Xunit;

namespace MediaTracker.Tests;

public class ParsersTests
{
    [Fact]
    public void CsvHelperMini_ShouldParseQuotedCsvAndJsonRecords()
    {
        // 1. Quoted CSV parsing
        var csv = "Title,Author,Notes\n\"The Lord of the Rings\",\"J.R.R. Tolkien\",\"Epic, \"\"classic\"\" fantasy\"\n\"1984\",\"George Orwell\",\"Dystopia\"";
        var records = CsvHelperMini.ReadRecords(csv).ToList();

        records.Should().HaveCount(2);
        records[0]["Title"].Should().Be("The Lord of the Rings");
        records[0]["Author"].Should().Be("J.R.R. Tolkien");
        records[0]["Notes"].Should().Be("Epic, \"classic\" fantasy");
        records[1]["Title"].Should().Be("1984");

        // 2. ReadAnyRecords with JSON
        var json = """
            [
              { "title": "Dune", "author": "Frank Herbert", "pages": "412" },
              { "title": "Neuromancer", "author": "William Gibson", "pages": "271" }
            ]
            """;
        var jsonRecords = CsvHelperMini.ReadAnyRecords(json);
        jsonRecords.Should().HaveCount(2);
        jsonRecords[0]["title"].Should().Be("Dune");
        jsonRecords[0]["author"].Should().Be("Frank Herbert");
    }

    [Fact]
    public void GoodreadsCsvParser_ShouldParseBooksAndRatings()
    {
        var csv = """
            Title,Author,Number of Pages,My Rating,Exclusive Shelf,Book Id
            "The Way of Kings","Brandon Sanderson",1007,5,read,7235533
            "Words of Radiance","Brandon Sanderson",1087,4,currently-reading,17332218
            "Oathbringer","Brandon Sanderson",1248,0,to-read,34002132
            """;

        var parsed = GoodreadsCsvParser.Parse(csv);
        parsed.Should().HaveCount(3);

        // Read shelf -> Completed, rating 5 * 2 = 10
        parsed[0].Title.Should().Be("The Way of Kings");
        parsed[0].Type.Should().Be("book");
        parsed[0].Status.Should().Be(MediaStatus.Completed);
        parsed[0].Score.Should().Be(10);
        parsed[0].TotalCount.Should().Be(1007);
        parsed[0].Author.Should().Be("Brandon Sanderson");
        parsed[0].ExternalId.Should().Be("7235533");
        parsed[0].ExternalSource.Should().Be("goodreads");

        // Currently-reading -> InProgress, rating 4 * 2 = 8
        parsed[1].Status.Should().Be(MediaStatus.InProgress);
        parsed[1].Score.Should().Be(8);

        // To-read -> Planned, rating 0 -> null
        parsed[2].Status.Should().Be(MediaStatus.Planned);
        parsed[2].Score.Should().BeNull();
    }

    [Fact]
    public void MalXmlParser_ShouldParseAnimeAndMangaXml()
    {
        var animeXml = """
            <?xml version="1.0" encoding="UTF-8" ?>
            <myanimelist>
                <myinfo>
                    <user_name>Tester</user_name>
                </myinfo>
                <anime>
                    <series_animedb_id>5114</series_animedb_id>
                    <series_title>Fullmetal Alchemist: Brotherhood</series_title>
                    <my_status>2</my_status>
                    <my_score>10</my_score>
                    <my_watched_episodes>64</my_watched_episodes>
                    <episodes>64</episodes>
                    <start_date>2009</start_date>
                </anime>
                <anime>
                    <series_animedb_id>16498</series_animedb_id>
                    <series_title>Shingeki no Kyojin</series_title>
                    <my_status>1</my_status>
                    <my_score>9</my_score>
                    <my_watched_episodes>15</my_watched_episodes>
                    <episodes>25</episodes>
                    <start_date>2013-04-07</start_date>
                </anime>
            </myanimelist>
            """;

        var parsedAnime = MalXmlParser.Parse(animeXml, manga: false);
        parsedAnime.Should().HaveCount(2);

        parsedAnime[0].Title.Should().Be("Fullmetal Alchemist: Brotherhood");
        parsedAnime[0].Type.Should().Be("anime");
        parsedAnime[0].Status.Should().Be(MediaStatus.Completed); // status 2 -> Completed
        parsedAnime[0].Score.Should().Be(10);
        parsedAnime[0].CurrentProgress.Should().Be(64);
        parsedAnime[0].TotalCount.Should().Be(64);
        parsedAnime[0].ReleaseYear.Should().Be(2009);
        parsedAnime[0].ExternalId.Should().Be("5114");

        parsedAnime[1].Title.Should().Be("Shingeki no Kyojin");
        parsedAnime[1].Status.Should().Be(MediaStatus.InProgress); // status 1 -> InProgress
        parsedAnime[1].CurrentProgress.Should().Be(15);
        parsedAnime[1].TotalCount.Should().Be(25);

        // Manga XML
        var mangaXml = """
            <?xml version="1.0" encoding="UTF-8" ?>
            <myanimelist>
                <manga>
                    <series_mangadb_id>2</series_mangadb_id>
                    <series_title>Berserk</series_title>
                    <my_reading_status>1</my_reading_status>
                    <my_score>10</my_score>
                    <my_read_chapters>364</my_read_chapters>
                    <chapters>380</chapters>
                    <my_read_volumes>41</my_read_volumes>
                    <volumes>42</volumes>
                </manga>
            </myanimelist>
            """;

        var parsedManga = MalXmlParser.Parse(mangaXml, manga: true);
        parsedManga.Should().HaveCount(1);
        parsedManga[0].Title.Should().Be("Berserk");
        parsedManga[0].Type.Should().Be("manga");
        parsedManga[0].Status.Should().Be(MediaStatus.InProgress);
        parsedManga[0].CurrentProgress.Should().Be(364);
        parsedManga[0].TotalCount.Should().Be(380);
        parsedManga[0].CurrentVolumes.Should().Be(41);
        parsedManga[0].TotalVolumes.Should().Be(42);
    }

    [Fact]
    public void MangalibParser_ShouldParseJsonAndCsvFormats()
    {
        // 1. JSON with Russian name and site mapping
        var json = """
            [
              { "rus_name": "Ван-Пис", "name": "One Piece", "status": 1, "user_chapters": 1122, "chapters": 1122, "user_rating": 10, "site_id": 1 },
              { "rus_name": "Берсерк", "eng_name": "Berserk", "status": "Брошено", "read_chapters": 36, "total_chapters": 374, "rating": 9, "site_id": 1 },
              { "rus_name": "Атака титанов (Аниме)", "status": 2, "site_id": 5 }
            ]
            """;

        var parsedJson = MangalibParser.Parse(json);
        parsedJson.Should().HaveCount(3);

        parsedJson[0].Title.Should().Be("Ван-Пис");
        parsedJson[0].Type.Should().Be("manga");
        parsedJson[0].Status.Should().Be(MediaStatus.InProgress);
        parsedJson[0].CurrentProgress.Should().Be(1122);
        parsedJson[0].TotalCount.Should().Be(1122);
        parsedJson[0].Score.Should().Be(10);

        parsedJson[1].Title.Should().Be("Берсерк");
        parsedJson[1].Status.Should().Be(MediaStatus.Dropped);
        parsedJson[1].CurrentProgress.Should().Be(36);
        parsedJson[1].TotalCount.Should().Be(374);

        parsedJson[2].Title.Should().Be("Атака титанов (Аниме)");
        parsedJson[2].Type.Should().Be("anime"); // site_id 5 -> anime

        // 2. CSV fallback
        var csv = "name,status,user_chapters,chapters,user_rating\n\"Соло-прокачка\",отложено,120,200,8";
        var parsedCsv = MangalibParser.Parse(csv);
        parsedCsv.Should().HaveCount(1);
        parsedCsv[0].Title.Should().Be("Соло-прокачка");
        parsedCsv[0].Status.Should().Be(MediaStatus.OnHold);
        parsedCsv[0].Score.Should().Be(8);
    }

    [Fact]
    public void MangalibParser_ShouldFilterOutFolderObjectsAndStandardFolderNames()
    {
        // 1. Raw folder object { id: 21, name: "Читаю" } has no media and no title-specific fields -> ignored
        var singleFolder = """{ "id": 21, "name": "Читаю" }""";
        MangalibParser.Parse(singleFolder).Should().BeEmpty();

        // 2. Array of folder objects from /api/bookmarks/folder/
        var foldersArray = """
            [
              { "id": 1, "name": "Читаю" },
              { "id": 2, "name": "В планах" },
              { "id": 3, "name": "Брошено" },
              { "id": 4, "name": "Прочитано" },
              { "id": 5, "name": "Любимые" },
              { "id": 6, "name": "Отложено" },
              { "id": 7, "name": "Жду" },
              { "id": 8, "name": "Удалено" },
              { "id": 9, "name": "Смотрю" },
              { "id": 10, "name": "Запланировано" },
              { "id": 11, "name": "Пересматриваю" }
            ]
            """;
        MangalibParser.Parse(foldersArray).Should().BeEmpty();

        // 3. Even if site_id is present, standard folder names are forbidden as titles
        var forbiddenTitles = """
            [
              { "rus_name": "Читаю", "site_id": 1 },
              { "name": "В планах", "site_id": 1 },
              { "media": { "rus_name": "Любимые", "slug_url": "favorites" } }
            ]
            """;
        MangalibParser.Parse(forbiddenTitles).Should().BeEmpty();

        // 4. Valid item is preserved while folder items are ignored
        var mixed = """
            [
              { "id": 21, "name": "Читаю" },
              { "rus_name": "Человек-бензопила", "site_id": 1, "slug_url": "chainsaw-man", "chap_count": 170 }
            ]
            """;
        var parsedMixed = MangalibParser.Parse(mixed);
        parsedMixed.Should().HaveCount(1);
        parsedMixed[0].Title.Should().Be("Человек-бензопила");
        parsedMixed[0].ExternalId.Should().Be("chainsaw-man");
    }

    [Fact]
    public void MangalibParser_AnimeLib_ShouldBeAnimeAndNeverBook()
    {
        var (type, source) = MangalibParser.DetermineTypeAndSource(5, "book");
        type.Should().Be("anime");
        source.Should().Be("AnimeLib");
    }

    [Fact]
    public async Task SqliteSchemaInitializer_ShouldCleanUpLegacyFakeFolderMediaItems()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"cleanup_test_{Guid.NewGuid():N}.db");
        try
        {
            var db = new MediaTracker.Server.Infrastructure.Persistence.AppDbContext($"Data Source={dbPath}");
            await db.Database.EnsureCreatedAsync();

            // Insert directly via SQL to simulate existing polluted database
            var id1 = Guid.NewGuid().ToString();
            var id2 = Guid.NewGuid().ToString();
            var id3 = Guid.NewGuid().ToString();
            await db.Database.ExecuteSqlRawAsync($"""
                INSERT INTO MediaItems (Id, Title, Status, SyncStatus, CreatedAt, UpdatedAt, MediaType, AutoRefreshIntervalDays, ImportSource, IsCustomEdited)
                VALUES 
                  ('{id1}', 'Читаю', 1, 0, '2026-01-01', '2026-01-01', 'manga', 7, 'MangaLib', 0),
                  ('{id2}', 'В планах', 2, 0, '2026-01-01', '2026-01-01', 'manga', 7, 'MangaLib', 0),
                  ('{id3}', 'Берсерк', 1, 0, '2026-01-01', '2026-01-01', 'manga', 7, 'MangaLib', 0);
                """);

            using (var cmd = db.Connection.CreateCommand())
            {
                cmd.CommandText = "SELECT COUNT(*) FROM MediaItems;";
                var countBefore = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                countBefore.Should().Be(3);
            }

            // Re-initialize to trigger migration cleanup. Schema migrations now run only when the
            // database is not stamped with the current PRAGMA user_version, so simulate a legacy
            // (pre-versioning) file first.
            using (var cmd = db.Connection.CreateCommand())
            {
                cmd.CommandText = "PRAGMA user_version = 0;";
                await cmd.ExecuteNonQueryAsync();
            }

            await MediaTracker.Server.Infrastructure.Persistence.SqliteSchemaInitializer.InitializeAsync(db.Connection);

            var itemsAfter = await db.LoadAllMediaItemsAsync();
            itemsAfter.Should().HaveCount(1);
            itemsAfter[0].Title.Should().Be("Берсерк");
        }
        finally
        {
            if (File.Exists(dbPath)) File.Delete(dbPath);
        }
    }

    [Fact]
    public async Task SqliteSchemaInitializer_ShouldSkipDdlWhenSchemaVersionMatches()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"schema_version_test_{Guid.NewGuid():N}.db");
        try
        {
            await using var db = new MediaTracker.Server.Infrastructure.Persistence.AppDbContext($"Data Source={dbPath}");
            await db.Database.EnsureCreatedAsync();

            using (var versionCmd = db.Connection.CreateCommand())
            {
                versionCmd.CommandText = "PRAGMA user_version;";
                Convert.ToInt32(await versionCmd.ExecuteScalarAsync()).Should().BeGreaterThan(0);
            }

            // A matching stamp must short-circuit the initializer: a manually dropped index stays
            // dropped on the next schema check instead of being recreated by the DDL batch.
            await db.Database.ExecuteSqlRawAsync("DROP INDEX IX_MediaItems_Status;");
            await db.Database.EnsureCreatedAsync();

            using (var checkCmd = db.Connection.CreateCommand())
            {
                checkCmd.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'IX_MediaItems_Status';";
                Convert.ToInt32(await checkCmd.ExecuteScalarAsync()).Should().Be(0);
            }
        }
        finally
        {
            if (File.Exists(dbPath)) File.Delete(dbPath);
        }
    }
}
