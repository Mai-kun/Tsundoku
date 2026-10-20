using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Common.Utilities;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import.Parsers;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence.Interceptors;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MediaDetailDto = MediaTracker.Server.Features.Media.MediaContract.MediaDetailDto;
using MediaJsonCache = MediaTracker.Server.Features.Media.MediaContract.MediaJsonCache;
using MediaListDto = MediaTracker.Server.Features.Media.MediaContract.MediaListDto;
using MediaResponseMapper = MediaTracker.Server.Features.Media.MediaContract.MediaResponseMapper;
using UpdateMediaRequest = MediaTracker.Server.Features.Media.UpdateMedia.UpdateMediaRequest;

namespace MediaTracker.Server.SelfChecks;

/// <summary>
/// Runnable assertion suite for the pure decision logic extracted out of the endpoint layer.
/// Run with: dotnet run --project MediaTracker.Server -- --selfcheck
/// </summary>
public static class RefactorSelfCheck
{
    public static int Run()
    {
        var failures = new List<string>();

        CheckSourceAliases(failures);
        CheckSpanParsing(failures);
        CheckSourceRegistryIsSelfContained(failures);
        CheckExternalUrlDetection(failures);
        CheckRatingsSerialization(failures);
        CheckMangaGapEnrichment(failures);
        CheckMangaFormatFromSources(failures);
        CheckMangaFormatMergePrefersOel(failures);
        CheckMangaGapEnrichmentDoesNotOverwrite(failures);
        CheckMergeKeepsRuntimeAndGenres(failures);
        CheckMergeCarriesCastAndTrailer(failures);
        CheckEnrichStoresGameDeveloper(failures);
        CheckMergeKeepsFinalChapterTotal(failures);
        CheckRelatedMediaSurvivesRoundTrip(failures);
        CheckMissingMetadataDrivesCascade(failures);
        CheckPartialDatesDoNotBecomeJanFirst(failures);
        CheckEnrichFillsMovieDisplayGaps(failures);
        CheckExplicitClearFlags(failures);
        CheckAchievementsSurviveUpdate(failures);
        CheckCustomEditFlagTracksManualWrites(failures);
        CheckSearchTypeFiltering(failures);
        CheckOverwriteRefresh(failures);
        CheckStatusTransitions(failures);
        CheckSeasonProgressStepper(failures);
        CheckNoInventedVolumes(failures);
        CheckReleaseStatusComputation(failures);
        CheckApiKeyLookup(failures);
        CheckCoverSizeLimit(failures);
        CheckCommandLineParsing(failures);
        CheckStaffAndCastSnapshots(failures);
        CheckKinopoiskEnumMapping(failures);
        CheckKinopoiskAirDateRange(failures);
        CheckKinopoiskEndDateOnlyWhenFinished(failures);
        CheckEnrichFillsEndDateAndStatus(failures);
        CheckEnrichStoresEpisodesForLiveAction(failures);
        CheckEnrichStoresEpisodeCountWithoutEpisodes(failures);
        CheckRealSeasonsCreateOneTvSeasonEach(failures);
        CheckRefreshDropsRatingsOfDisabledSources(failures);
        CheckSqliteTuningIsPreserved(failures);
        CheckMetadataProvidersAreDiscovered(failures);
        CheckImdbSuggestionPartition(failures);
        CheckImdbTypeClassification(failures);
        CheckSourcePriorityVersionBump(failures);
        CheckSimklSearchSegments(failures);
        CheckBookPageCountSurvivesMerge(failures);
        CheckProviderConnectionTestIsNotShadowed(failures);
        CheckListPayloadStaysLight(failures);
        CheckListAndDetailTotalsAgree(failures);
        CheckStatusWireContract(failures);
        CheckMangaDexRelationTypes(failures);
        CheckKitsuRatingMapping(failures);
        CheckSteamVerticalCovers(failures);
        CheckAdvancedStatsCalculation(failures);
        CheckAllMetadataProvidersSupportGenres(failures);
        CheckLetterboxdCsvImportParser(failures);
        CheckAniListImportParser(failures);
        CheckMangalibImportParser(failures);
        CheckCustomImportParser(failures);
        CheckSteamLibraryImportParser(failures);
        CheckImportHealing(failures);
        CheckHistoryEventsFiltering(failures);
        CheckSmartListEvaluator(failures);

        if (failures.Count == 0)
        {
            Console.WriteLine("SELFCHECK OK - all assertions passed.");
            return 0;
        }

        Console.WriteLine($"SELFCHECK FAILED - {failures.Count} assertion(s):");
        foreach (var failure in failures)
        {
            Console.WriteLine("  - " + failure);
        }

        return 1;
    }

    private static void CheckLetterboxdCsvImportParser(List<string> failures)
    {
        var parsed = LetterboxdCsvParser.Parse("Name,Year,Rating,Watched Date\n\"Title, The\",1999,4.5,2024-03-02");
        AssertEqual(failures, 1, parsed.Count, "Letterboxd CSV record count");
        if (parsed.Count == 1)
        {
            AssertEqual(failures, "Title, The", parsed[0].Title, "Letterboxd quoted comma title");
            AssertEqual<int?>(failures, 9, parsed[0].Score, "Letterboxd half-star conversion");
            AssertEqual<int?>(failures, 1999, parsed[0].ReleaseYear, "Letterboxd release year");
        }
    }
    private static void CheckAniListImportParser(List<string> failures)
    {
        var json = """
            [
              {
                "progress": 12,
                "status": "CURRENT",
                "score": 87,
                "media": { "id": 5114, "type": "ANIME", "episodes": 64, "title": { "english": "Fullmetal Alchemist: Brotherhood", "romaji": "Hagane no Renkinjutsushi", "native": "鋼の錬金術師" } }
              },
              {
                "progress": 30,
                "listStatus": "PAUSED",
                "score": 8,
                "media": { "id": 30002, "type": "MANGA", "chapters": 364, "title": { "english": null, "romaji": "Berserk", "native": "ベルセルク" } }
              }
            ]
            """;
        var parsed = AniListImportParser.Parse(json, mangaFile: false);
        AssertEqual(failures, 2, parsed.Count, "AniList entry count");
        if (parsed.Count == 2)
        {
            AssertEqual(failures, "Fullmetal Alchemist: Brotherhood", parsed[0].Title, "AniList english title preferred");
            AssertEqual(failures, "anime", parsed[0].Type, "AniList ANIME type");
            AssertEqual(failures, MediaStatus.InProgress, parsed[0].Status, "AniList CURRENT maps to in-progress");
            AssertEqual<int?>(failures, 9, parsed[0].Score, "AniList 100-point score normalizes to 10");
            AssertEqual<int?>(failures, 64, parsed[0].TotalCount, "AniList episodes total");
            AssertEqual(failures, "5114", parsed[0].ExternalId, "AniList external id");
            AssertEqual(failures, "Berserk", parsed[1].Title, "AniList romaji fallback title");
            AssertEqual(failures, "manga", parsed[1].Type, "AniList MANGA type");
            AssertEqual(failures, MediaStatus.OnHold, parsed[1].Status, "AniList listStatus PAUSED maps to on-hold");
        }

        var graphQl = """
            {
              "data": {
                "MediaListCollection": {
                  "lists": [
                    {
                      "entries": [
                        {
                          "progress": 3,
                          "status": "PLANNING",
                          "score": 0,
                          "media": {
                            "id": 1,
                            "type": "ANIME",
                            "episodes": 12,
                            "title": { "english": "Frieren", "romaji": "Sousou no Frieren", "native": "葬送のフリーレン" },
                            "coverImage": { "extraLarge": "https://cdn.example/frieren_xl.jpg", "large": "https://cdn.example/frieren_l.jpg" },
                            "description": "<p>After a 10-year quest...</p>",
                            "genres": ["Adventure", "Fantasy"],
                            "startDate": { "year": 2023, "month": 9, "day": 29 },
                            "endDate": { "year": 2024, "month": 3, "day": 22 },
                            "status": "FINISHED",
                            "averageScore": 91,
                            "studios": { "nodes": [ { "name": "Madhouse" } ] },
                            "duration": 24
                          }
                        }
                      ]
                    }
                  ]
                }
              }
            }
            """;
        var fromProfile = AniListImportParser.Parse(graphQl, mangaFile: false);
        AssertEqual(failures, 1, fromProfile.Count, "AniList GraphQL collection entry count");
        if (fromProfile.Count == 1)
        {
            AssertEqual(failures, "Frieren", fromProfile[0].Title, "AniList GraphQL title");
            AssertEqual(failures, MediaStatus.Planned, fromProfile[0].Status, "AniList GraphQL PLANNING maps to planned");
            AssertEqual<int?>(failures, null, fromProfile[0].Score, "AniList GraphQL zero score becomes null");
            AssertEqual(failures, "https://cdn.example/frieren_xl.jpg", fromProfile[0].CoverUrl, "AniList GraphQL coverImage");
            AssertEqual(failures, "After a 10-year quest...", fromProfile[0].Description, "AniList GraphQL description");
            AssertEqual(failures, "Adventure, Fantasy", fromProfile[0].Genres, "AniList GraphQL genres");
            AssertEqual(failures, "2023-09-29", fromProfile[0].ReleaseDate, "AniList GraphQL releaseDate");
            AssertEqual(failures, "2024-03-22", fromProfile[0].EndDate, "AniList GraphQL endDate");
            AssertEqual(failures, "FINISHED", fromProfile[0].ReleaseStatus, "AniList GraphQL releaseStatus");
            AssertEqual<double?>(failures, 9.1, fromProfile[0].Rating, "AniList GraphQL rating");
            AssertEqual(failures, "Madhouse", fromProfile[0].Studio, "AniList GraphQL studio");
            AssertEqual(failures, "Sousou no Frieren", fromProfile[0].RomajiTitle, "AniList GraphQL romaji");
            AssertEqual(failures, "葬送のフリーレン", fromProfile[0].OriginalTitle, "AniList GraphQL native");
            AssertEqual<int?>(failures, 24, fromProfile[0].DurationMinutes, "AniList GraphQL duration");
        }

        var combined = """{"animelist":[{ "progress": 1, "status": "CURRENT", "score": 8, "media": { "id": 1, "type": "ANIME", "episodes": 12, "title": { "english": "Frieren" } } }],"mangalist":[{ "progress": 5, "status": "COMPLETED", "score": 10, "media": { "id": 2, "type": "MANGA", "chapters": 100, "title": { "english": "Vinland Saga" } } }]}""";
        var merged = AniListImportParser.Parse(combined, mangaFile: false);
        AssertEqual(failures, 2, merged.Count, "AniList combined export flattens both lists");
        if (merged.Count == 2)
        {
            AssertEqual(failures, "anime", merged[0].Type, "AniList combined anime entry type");
            AssertEqual(failures, "manga", merged[1].Type, "AniList combined manga entry type");
        }

        // Fuzzy dates with null month / day
        var fuzzyDatesJson = """
            [
              {
                "progress": 1,
                "status": "CURRENT",
                "media": {
                  "id": 100,
                  "type": "ANIME",
                  "title": { "english": "Fuzzy Year Only" },
                  "startDate": { "year": 2021, "month": null, "day": null },
                  "endDate": { "year": 2022, "month": 6, "day": null }
                }
              },
              {
                "progress": 2,
                "status": "COMPLETED",
                "media": {
                  "id": 101,
                  "type": "MANGA",
                  "title": { "romaji": "Fuzzy All Nulls" },
                  "startDate": { "year": null, "month": null, "day": null },
                  "endDate": null
                }
              }
            ]
            """;
        var fuzzyParsed = AniListImportParser.Parse(fuzzyDatesJson, mangaFile: false);
        AssertEqual(failures, 2, fuzzyParsed.Count, "AniList fuzzy dates entry count");
        if (fuzzyParsed.Count == 2)
        {
            AssertEqual(failures, "2021", fuzzyParsed[0].ReleaseDate, "AniList fuzzy date year-only formatted as yyyy");
            AssertEqual(failures, "2022-06", fuzzyParsed[0].EndDate, "AniList fuzzy date year-month formatted as yyyy-MM");
            AssertEqual(failures, null, fuzzyParsed[1].ReleaseDate, "AniList all-null fuzzy date is null");
        }

        // GraphQL error envelope handling
        var errorJson = """{"errors":[{"message":"User not found","status":404}],"data":null}""";
        try
        {
            AniListImportParser.Parse(errorJson, mangaFile: false);
            failures.Add("Expected AniListImportParser to throw on GraphQL errors envelope");
        }
        catch (FormatException ex)
        {
            AssertEqual(failures, true, ex.Message.Contains("User not found"), "AniList error message extracted");
        }
    }

    private static void CheckMangalibImportParser(List<string> failures)
    {
        var json = """
            [
              { "rus_name": "Ван-Пис", "name": "One Piece", "status": 1, "user_chapters": 1122, "chapters": 1122, "user_rating": 10 },
              { "rus_name": "Берсерк", "eng_name": "Berserk", "status": "Брошено", "read_chapters": 36, "total_chapters": 374, "rating": 9 }
            ]
            """;
        var parsed = MangalibParser.Parse(json);
        AssertEqual(failures, 2, parsed.Count, "MangaLib JSON entry count");
        if (parsed.Count == 2)
        {
            AssertEqual(failures, "Ван-Пис", parsed[0].Title, "MangaLib rus_name preferred");
            AssertEqual(failures, "manga", parsed[0].Type, "MangaLib type is always manga");
            AssertEqual(failures, MediaStatus.InProgress, parsed[0].Status, "MangaLib numeric status 1 maps to in-progress");
            AssertEqual<int?>(failures, 1122, parsed[0].CurrentProgress, "MangaLib user_chapters");
            AssertEqual<int?>(failures, 10, parsed[0].Score, "MangaLib user_rating");
            AssertEqual(failures, "MangaLib", parsed[0].ExternalSource, "MangaLib external source");
            AssertEqual(failures, MediaStatus.Dropped, parsed[1].Status, "MangaLib string status брошено maps to dropped");
            AssertEqual<int?>(failures, 36, parsed[1].CurrentProgress, "MangaLib read_chapters fallback");
            AssertEqual<int?>(failures, 374, parsed[1].TotalCount, "MangaLib total_chapters fallback");
        }

        var csv = MangalibParser.Parse("name,status,user_chapters,chapters,user_rating\n\"Соло-levelling\",отложено,120,200,8");
        AssertEqual(failures, 1, csv.Count, "MangaLib CSV entry count");
        if (csv.Count == 1)
        {
            AssertEqual(failures, MediaStatus.OnHold, csv[0].Status, "MangaLib CSV отложено maps to on-hold");
            AssertEqual<int?>(failures, 8, csv[0].Score, "MangaLib CSV rating");
        }
    }

    private static void CheckCustomImportParser(List<string> failures)
    {
        var json = """
            [
              { "title": "Тетрадь смерти", "type": "сериал", "status": "в планах", "score": 9, "progress": 37, "totalCount": 37, "director": "Тэцуро Араки", "year": 2006 },
              { "title": "Disco Elysium", "type": "game", "status": 2, "progress": 40, "studio": "ZA/UM" },
              { "type": "movie", "status": "completed" }
            ]
            """;
        var parsed = CustomImportParser.Parse(json);
        AssertEqual(failures, 2, parsed.Count, "Custom JSON skips titleless rows");
        if (parsed.Count == 2)
        {
            AssertEqual(failures, "Тетрадь смерти", parsed[0].Title, "Custom title");
            AssertEqual(failures, "tvshow", parsed[0].Type, "Custom Russian тип сериал maps to tvshow");
            AssertEqual(failures, MediaStatus.Planned, parsed[0].Status, "Custom в планах maps to planned");
            AssertEqual<int?>(failures, 9, parsed[0].Score, "Custom score");
            AssertEqual<int?>(failures, 37, parsed[0].CurrentProgress, "Custom progress");
            AssertEqual<int?>(failures, 2006, parsed[0].ReleaseYear, "Custom year");
            AssertEqual(failures, "Тэцуро Араки", parsed[0].Author, "Custom director becomes author");
            AssertEqual(failures, "game", parsed[1].Type, "Custom game type");
            AssertEqual(failures, MediaStatus.Completed, parsed[1].Status, "Custom numeric status 2 maps to completed");
            AssertEqual(failures, "ZA/UM", parsed[1].Author, "Custom studio becomes author");
        }

        var csv = CustomImportParser.Parse("title,type,status,score\n\"Наруто\",Манга,читаю,7\n\"\",anime,completed,5");
        AssertEqual(failures, 1, csv.Count, "Custom CSV skips titleless rows");
        if (csv.Count == 1)
        {
            AssertEqual(failures, "manga", csv[0].Type, "Custom CSV Russian тип манга");
            AssertEqual(failures, MediaStatus.InProgress, csv[0].Status, "Custom CSV читаю maps to in-progress");
        }
    }

    private static void CheckSteamLibraryImportParser(List<string> failures)
    {
        var steamJson = """{"games":[{"appid":367520,"name":"Hollow Knight","playtime_forever":120}]}""";
        var steamGames = SteamLibraryParser.Parse(steamJson);
        AssertEqual(failures, 1, steamGames.Count, "Steam games count");
        if (steamGames.Count == 1)
        {
            AssertEqual(failures, "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg", steamGames[0].CoverUrl, "Steam library 600x900 cover");
            AssertEqual(failures, "PC", steamGames[0].Platform, "Steam platform is PC");
            AssertEqual(failures, "Steam", steamGames[0].ExternalSource, "Steam external source");
            AssertEqual(failures, "367520", steamGames[0].ExternalId, "Steam external id");
            AssertEqual(failures, 2, steamGames[0].CurrentProgress, "Steam playtime hours");
        }
    }

    private static void CheckImportHealing(List<string> failures)
    {
        using var connection = new SqliteConnection("DataSource=:memory:");
        connection.Open();
        var options = new DbContextOptionsBuilder<AppDbContext>().UseSqlite(connection).Options;
        using var db = new AppDbContext(options);
        db.Database.EnsureCreated();

        // 1. Existing empty manga row
        var existingManga = new Manga
        {
            Title = "Demon King of the Royal Class",
            ExternalId = "12345",
            ExternalSource = "AniList"
        };
        db.Manga.Add(existingManga);

        // 2. Existing empty game row
        var existingGame = new VideoGame
        {
            Title = "Hollow Knight",
            Platform = "Steam",
            ExternalId = "367520",
            ExternalSource = "Steam"
        };
        db.Games.Add(existingGame);
        db.SaveChanges();

        var handler = new ImportMediaHandler(
            db,
            new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage())),
            new ConfigurationBuilder().Build(),
            Options.Create(new ExternalApiOptions()));

        var anilistJson = """
            [
              {
                "progress": 50,
                "status": "CURRENT",
                "score": 85,
                "media": {
                  "id": 12345,
                  "type": "MANGA",
                  "chapters": 120,
                  "title": { "english": "Demon King of the Royal Class", "romaji": "Demon King Romaji" },
                  "coverImage": { "extraLarge": "https://s4.anilist.co/cover/12345.jpg" },
                  "description": "<p>A great story about royal academy</p>",
                  "genres": ["Action", "Fantasy", "School"],
                  "startDate": { "year": 2022, "month": 3, "day": 15 },
                  "status": "RELEASING",
                  "averageScore": 84,
                  "staff": { "edges": [ { "role": "Story & Art", "node": { "name": { "full": "Geul Jangi" } } } ] }
                }
              }
            ]
            """;
        var fileBytes = global::System.Text.Encoding.UTF8.GetBytes(anilistJson);
        using var stream = new MemoryStream(fileBytes);
        var formFile = new FormFile(stream, 0, fileBytes.Length, "file", "anilist.json");
        var result = handler.ImportFileAsync(new ImportFileRequest(formFile, "anilist", SkipDuplicates: true), CancellationToken.None).GetAwaiter().GetResult();

        AssertEqual(failures, 1, result.TotalFound, "Import total found");
        AssertEqual(failures, 0, result.ImportedCount, "Import imported count (skipped duplicate)");
        AssertEqual(failures, 1, result.SkippedDuplicates, "Import duplicate count");

        var healedManga = db.Manga.Single(m => m.ExternalId == "12345");
        AssertEqual(failures, "https://s4.anilist.co/cover/12345.jpg", healedManga.CoverUrl, "Healed manga has cover");
        AssertEqual(failures, "A great story about royal academy", healedManga.Description, "Healed manga has description");
        AssertEqual(failures, "Action, Fantasy, School", healedManga.Genres, "Healed manga has genres");
        AssertEqual(failures, "Geul Jangi", healedManga.Author, "Healed manga has author");
        AssertEqual(failures, "Demon King Romaji", healedManga.RomajiTitle, "Healed manga has romaji");
        AssertEqual(failures, "RELEASING", healedManga.ReleaseStatus, "Healed manga has release status");
        AssertEqual<double?>(failures, 8.4, healedManga.ExternalRating, "Healed manga has rating");
        AssertTrue(failures, healedManga.ExternalRatingsJson is not null && healedManga.ExternalRatingsJson.Contains("8.4"), "Healed manga has external ratings JSON");

        // Now test Steam game healing
        var steamJson = """{"games":[{"appid":367520,"name":"Hollow Knight","playtime_forever":120}]}""";
        var steamBytes = global::System.Text.Encoding.UTF8.GetBytes(steamJson);
        using var steamStream = new MemoryStream(steamBytes);
        var steamFormFile = new FormFile(steamStream, 0, steamBytes.Length, "file", "steam.json");
        handler.ImportFileAsync(new ImportFileRequest(steamFormFile, "steam", SkipDuplicates: true), CancellationToken.None).GetAwaiter().GetResult();

        var healedGame = db.Games.Single(g => g.ExternalId == "367520");
        AssertEqual(failures, "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg", healedGame.CoverUrl, "Healed steam game has 600x900 cover");
        AssertEqual(failures, "PC", healedGame.Platform, "Healed steam game platform is PC");
    }

    private static void CheckHistoryEventsFiltering(List<string> failures)
    {
        using var connection = new SqliteConnection("DataSource=:memory:");
        connection.Open();
        var options = new DbContextOptionsBuilder<AppDbContext>().UseSqlite(connection).Options;
        using var db = new AppDbContext(options);
        db.Database.EnsureCreated();

        var media1 = Guid.NewGuid();
        var media2 = Guid.NewGuid();
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var yesterday = today.AddDays(-1);

        db.Books.Add(new Book { Id = media1, Title = "Book 1", Author = "Author 1", CurrentPage = 10 });
        db.TvShows.Add(new TvShow { Id = media2, Title = "Show 1" });

        var event1 = new MediaEvent
        {
            MediaId = media1,
            Type = MediaEventType.ProgressChanged,
            OldValue = "10 стр.",
            NewValue = "20 стр.",
            CreatedAt = today.ToDateTime(new TimeOnly(10, 0), DateTimeKind.Utc)
        };
        var event2 = new MediaEvent
        {
            MediaId = media1,
            Type = MediaEventType.StatusChanged,
            OldValue = "Planned",
            NewValue = "InProgress",
            CreatedAt = yesterday.ToDateTime(new TimeOnly(12, 0), DateTimeKind.Utc)
        };
        var event3 = new MediaEvent
        {
            MediaId = media2,
            Type = MediaEventType.ProgressChanged,
            OldValue = "S1 E1",
            NewValue = "S1 E2",
            CreatedAt = today.ToDateTime(new TimeOnly(15, 0), DateTimeKind.Utc)
        };

        db.Events.AddRange(event1, event2, event3);
        db.SaveChanges();

        var handler = new GetHistoryEventsHandler(db);

        var media1Events = handler.HandleAsync(new GetHistoryEventsQuery(MediaId: media1), CancellationToken.None).GetAwaiter().GetResult().Value!;
        AssertEqual(failures, 2, media1Events.Count, "media1 has 2 events");

        var todayEvents = handler.HandleAsync(new GetHistoryEventsQuery(Date: today), CancellationToken.None).GetAwaiter().GetResult().Value!;
        AssertEqual(failures, 2, todayEvents.Count, "today has 2 events");

        var bothEvents = handler.HandleAsync(new GetHistoryEventsQuery(MediaId: media1, Date: today), CancellationToken.None).GetAwaiter().GetResult().Value!;
        AssertEqual(failures, 1, bothEvents.Count, "media1 today has 1 event");
        AssertEqual(failures, "10 стр.", bothEvents[0].OldValue, "old value matches");
        AssertEqual(failures, "20 стр.", bothEvents[0].NewValue, "new value matches");
    }

    private static void CheckSourceAliases(List<string> failures)
    {
        AssertEqual(failures, "jikan", MediaMerger.NormalizeSourceKey("MyAnimeList"), "MAL alias");
        AssertEqual(failures, "jikan", MediaMerger.NormalizeSourceKey("mal"), "mal alias");
        AssertEqual(failures, "thetvdb", MediaMerger.NormalizeSourceKey("TheTVDB"), "tvdb alias");
        AssertEqual(
            failures,
            "thetvdb",
            MediaMerger.NormalizeSourceKey("tvdb"),
            "tvdb short alias"
        );
        AssertEqual(
            failures,
            "googlebooks",
            MediaMerger.NormalizeSourceKey("google"),
            "google alias"
        );
        AssertEqual(
            failures,
            "tmdb",
            MediaMerger.NormalizeSourceKey("The Movie Database"),
            "tmdb long alias"
        );
        AssertEqual(
            failures,
            "anilist",
            MediaMerger.NormalizeSourceKey("AniList"),
            "anilist alias"
        );
        AssertEqual(
            failures,
            "unknownthing",
            MediaMerger.NormalizeSourceKey("UnknownThing"),
            "unknown falls through"
        );

        AssertEqual(
            failures,
            "MyAnimeList",
            MediaMerger.GetCanonicalSourceName("mal"),
            "canonical exact"
        );
        AssertEqual(
            failures,
            "TheTVDB",
            MediaMerger.GetCanonicalSourceName("thetvdb"),
            "canonical longest-wins"
        );
        AssertEqual(
            failures,
            string.Empty,
            MediaMerger.GetCanonicalSourceName("  "),
            "canonical blank"
        );
    }

    private static void CheckSpanParsing(List<string> failures)
    {
        AssertEqual(failures, 49, SpanParserExtensions.ParseDurationMinutes("49 min"), "span parser reads minute duration");
        AssertEqual(failures, 142, SpanParserExtensions.ParseDurationMinutes("142 min"), "span parser reads long minute duration");
        AssertEqual(failures, 90, SpanParserExtensions.ParseDurationMinutes("1h 30m"), "span parser reads hour and minute duration");
        AssertEqual(failures, 120, SpanParserExtensions.ParseDurationMinutes("2h"), "span parser reads hour duration");
        AssertEqual(failures, 2008, SpanParserExtensions.ParseYearFromDateString("2008-01-20"), "span parser reads ISO date year");
    }

    /// <summary>
    /// The whole point of the registry is that a provider file is the only place a source is declared.
    /// These assertions fail the moment that stops being true: an id nothing resolves to, a type missing
    /// from the cascade, or two sources sharing an id.
    /// </summary>
    private static void CheckSourceRegistryIsSelfContained(List<string> failures)
    {
        var sources = MetadataSourceRegistry.All;

        AssertTrue(failures, sources.Count > 0, "the registry discovered at least one source");

        var ids = sources.Select(s => s.Id).ToList();
        AssertEqual(
            failures,
            ids.Count,
            ids.Distinct(StringComparer.OrdinalIgnoreCase).Count(),
            "source ids are unique"
        );

        foreach (var descriptor in sources)
        {
            // Every source must be reachable under its own id, or MediaMerger's normalizer would resolve
            // a settings key to a provider the container cannot hand out.
            AssertEqual(
                failures,
                descriptor.Id,
                MediaMerger.NormalizeSourceKey(descriptor.Id),
                $"'{descriptor.Id}' normalizes to itself"
            );

            AssertTrue(
                failures,
                Uri.TryCreate(descriptor.BaseAddress, UriKind.Absolute, out _),
                $"'{descriptor.Id}' declares an absolute base address"
            );

            AssertTrue(
                failures,
                descriptor.MediaTypes.Count > 0,
                $"'{descriptor.Id}' serves at least one media type"
            );

            foreach (var mediaType in descriptor.MediaTypes)
            {
                AssertTrue(
                    failures,
                    SourcePriorityService.DefaultPriorities.TryGetValue(mediaType, out var cascade)
                        && cascade.Contains(descriptor.Id, StringComparer.OrdinalIgnoreCase),
                    $"'{descriptor.Id}' appears in the '{mediaType}' cascade"
                );
            }
        }

        // The cascade order is what fills gaps, so a source must never sort behind a source that only
        // exists to fill gaps for it. These two assertions pin the shipped order exactly.
        AssertEqual(
            failures,
            "anilist,shikimori,kitsu,simkl,jikan",
            string.Join(',', SourcePriorityService.DefaultPriorities["anime"]),
            "anime cascade order"
        );
        AssertEqual(
            failures,
            "tmdb,imdb,kinopoisk,simkl,thetvdb",
            string.Join(',', SourcePriorityService.DefaultPriorities["movie"]),
            "movie cascade order"
        );
        AssertEqual(
            failures,
            "anilist,shikimori,kitsu,mangadex,mangaupdates,jikan",
            string.Join(',', SourcePriorityService.DefaultPriorities["manga"]),
            "manga cascade order"
        );
        AssertEqual(
            failures,
            "rawg,steam,igdb",
            string.Join(',', SourcePriorityService.DefaultPriorities["game"]),
            "game cascade order"
        );
        AssertEqual(
            failures,
            "openlibrary,googlebooks",
            string.Join(',', SourcePriorityService.DefaultPriorities["book"]),
            "book cascade order"
        );
    }

    private static void CheckExternalUrlDetection(List<string> failures)
    {
        AssertTrue(
            failures,
            MediaMetadataApplier.IsExternalUrl("https://cdn.example/a.jpg"),
            "https is external"
        );
        AssertTrue(
            failures,
            MediaMetadataApplier.IsExternalUrl("http://cdn.example/a.jpg"),
            "http is external"
        );
        AssertFalse(
            failures,
            MediaMetadataApplier.IsExternalUrl("/covers/x.webp"),
            "local cover is not external"
        );
        AssertFalse(
            failures,
            MediaMetadataApplier.IsExternalUrl("data:image/png;base64,AAA"),
            "data uri is not external"
        );
        AssertFalse(failures, MediaMetadataApplier.IsExternalUrl(null), "null is not external");
    }

    private static void CheckRatingsSerialization(List<string> failures)
    {
        var json = MediaMetadataApplier.SerializeRatings([
            new ExternalRatingDto
            {
                Source = "AniList",
                Rating = 8.5,
                Votes = 1200,
            },
        ]);

        using var document = JsonDocument.Parse(json);
        var first = document.RootElement[0];

        // The UI reads .score first, so the persisted key must be "score", not "rating".
        AssertEqual(
            failures,
            "AniList",
            first.GetProperty("source").GetString(),
            "rating source key"
        );
        AssertEqual(failures, 8.5, first.GetProperty("score").GetDouble(), "rating score key");
        AssertEqual(failures, 1200, first.GetProperty("votes").GetInt32(), "rating votes key");
    }

    private static void CheckEnrichFillsMovieDisplayGaps(List<string> failures)
    {
        var movie = new Movie { Title = "Дюна" };
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Дюна",
            Type = "movie",
            RuntimeMinutes = 155,
            Studio = "Legendary Pictures",
            Author = "Denis Villeneuve",
        };

        AssertTrue(
            failures,
            MediaMetadataApplier.ApplyIfMissing(movie, external),
            "enrich reports a change"
        );
        AssertEqual(failures, 155, movie.DurationMinutes, "enrich fills the runtime");
        AssertEqual(failures, "Legendary Pictures", movie.Studio, "enrich fills the studio");
        AssertEqual(failures, "Denis Villeneuve", movie.Director, "enrich fills the director");

        // A second pass must not overwrite what is already there.
        MediaMetadataApplier.ApplyIfMissing(
            movie,
            external with
            {
                RuntimeMinutes = 200,
                Studio = "Other",
            }
        );
        AssertEqual(failures, 155, movie.DurationMinutes, "enrich keeps the existing runtime");
        AssertEqual(
            failures,
            "Legendary Pictures",
            movie.Studio,
            "enrich keeps the existing studio"
        );
    }

    private static void CheckExplicitClearFlags(List<string> failures)
    {
        var item = new VideoGame
        {
            Title = "Silksong",
            Platform = "PC",
            UserPlatform = "PC",
        };

        // An omitted field means "not supplied" and must leave the stored value alone.
        MediaItemUpdater.Apply(item, new UpdateMediaRequest { Title = "Silksong" });
        AssertEqual(failures, "PC", item.UserPlatform, "an omitted field keeps the stored value");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { ClearUserPlatform = true });
        AssertTrue(failures, item.UserPlatform is null, "an explicit clear empties the platform");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { WatchedOn = "Kinopoisk" });
        AssertEqual(failures, "Kinopoisk", item.WatchedOn, "watched-on is stored");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { ClearWatchedOn = true });
        AssertTrue(failures, item.WatchedOn is null, "an explicit clear empties watched-on");
    }

    /// <summary>
    /// The overwrite prompt is only useful if the flag is accurate in both directions: a person
    /// editing a field has to arm it, and the routine progress/platform/cache writes that share
    /// the same endpoint must not. Missing the second half means every watched item asked the user
    /// to protect edits they never made.
    /// </summary>
    private static void CheckCustomEditFlagTracksManualWrites(List<string> failures)
    {
        var item = new Movie { Title = "Dune", Director = "Villeneuve" };

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { WatchedOn = "Kinopoisk" });
        AssertTrue(
            failures,
            !item.IsCustomEdited,
            "picking a streaming site does not count as a manual field edit");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { AchievementsJson = "[]" });
        AssertTrue(
            failures,
            !item.IsCustomEdited,
            "writing the achievements cache does not count as a manual field edit");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { CurrentVolume = 3 });
        AssertTrue(
            failures,
            !item.IsCustomEdited,
            "a progress counter does not count as a manual field edit");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { Title = "Dune" });
        AssertTrue(
            failures,
            !item.IsCustomEdited,
            "resending the unchanged title does not arm the prompt");

        MediaItemUpdater.Apply(item, new UpdateMediaRequest { Notes = " rewatched " });
        AssertTrue(
            failures,
            item.IsCustomEdited,
            "typing into the notes field arms the overwrite prompt");

        // The flag is sticky: a later cache write must not silently disarm the prompt.
        MediaItemUpdater.Apply(item, new UpdateMediaRequest { RecommendationsJson = "[]" });
        AssertTrue(
            failures,
            item.IsCustomEdited,
            "the flag survives an unrelated later write");

        AssertEqual(
            failures,
            " rewatched ",
            item.Notes,
            "safe-merge input still stores the user's notes");
    }

    private static void CheckAchievementsSurviveUpdate(List<string> failures)
    {
        var game = new VideoGame { Title = "Hollow Knight", Platform = "PC" };
        const string json = "[\"Blasphemous\",\"Quarantine\"]";

        MediaItemUpdater.Apply(game, new UpdateMediaRequest { UnlockedAchievements = json });
        AssertEqual(
            failures,
            json,
            game.UnlockedAchievements,
            "achievements are persisted by the updater"
        );

        MediaItemUpdater.Apply(game, new UpdateMediaRequest { UserPlatform = "PC" });
        AssertEqual(
            failures,
            json,
            game.UnlockedAchievements,
            "an unrelated update must not wipe the achievements"
        );
    }

    private static void CheckMergeKeepsRuntimeAndGenres(List<string> failures)
    {
        var primary = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Дюна",
            Type = "movie",
            RuntimeMinutes = 155,
        };
        var fallback = new ExternalMediaDto
        {
            ExternalId = "2",
            Title = "Дюна",
            Type = "movie",
            Studio = "Legendary Pictures",
            Genres = ["Sci-Fi"],
        };

        var merged = MediaMerger.Merge(primary, fallback);

        AssertEqual(
            failures,
            155,
            merged.RuntimeMinutes,
            "merge keeps a runtime the second source lacks"
        );
        AssertEqual(failures, "Legendary Pictures", merged.Studio, "merge fills a missing studio");
        AssertEqual(
            failures,
            1,
            merged.Genres?.Count,
            "merge fills genres the primary source lacks"
        );
    }

    private static void CheckStaffAndCastSnapshots(List<string> failures)
    {
        // Anime: a voice actor clears two roles, staff carries photos, both survive the JSON round trip.
        var anime = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Re:Zero",
            Type = "anime",
            OriginalTitle = "Re:ゼロから始める異世界生活",
            Staff =
            [
                new ExternalStaffMemberDto("Masahiro Watanabe", "Director", "https://s4.anilist.co/file/anilistcdn/staff/large/d1.jpg"),
                new ExternalStaffMemberDto("Kyuta Sakai", "Character Design, Chief Animation Director", "https://s4.anilist.co/file/anilistcdn/staff/large/d2.jpg"),
            ],
            Cast =
            [
                new CastMemberDto("Rie Takahashi", "Emilia", "https://s4.anilist.co/file/anilistcdn/character/large/v1.jpg")
                {
                    CharacterImageUrl = "https://s4.anilist.co/file/anilistcdn/character/large/c1.jpg",
                    CharacterRole = "MAIN",
                    VoiceActorName = "Rie Takahashi",
                    VoiceActorImageUrl = "https://s4.anilist.co/file/anilistcdn/staff/large/v1.jpg",
                },
            ],
        };

        var show = new TvShow
        {
            Title = "Re:Zero",
            Studio = "White Fox",
            IsAnime = true,
        };
        MediaMetadataApplier
            .ApplyOverwriteAsync(show, anime, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertEqual(failures, "Re:ゼロから始める異世界生活", show.OriginalTitle, "refresh stores the native title");
        var staff = MediaJsonCache.Deserialize<ExternalStaffMemberDto>(show.StaffJson);
        AssertEqual(failures, 2, staff.Count, "staff snapshot survives the round trip");
        AssertEqual(
            failures,
            "https://s4.anilist.co/file/anilistcdn/staff/large/d1.jpg",
            staff[0].ImageUrl,
            "staff keeps the medium photo");
        var cast = MediaJsonCache.Deserialize<CastMemberDto>(show.CastJson);
        AssertEqual(failures, "Rie Takahashi", cast.Single().VoiceActorName, "cast keeps the Japanese voice actor");
        AssertEqual(
            failures,
            "https://s4.anilist.co/file/anilistcdn/character/large/c1.jpg",
            cast.Single().CharacterImageUrl,
            "cast keeps the character portrait");

        // Manga: entries are pure characters — name, portrait and MAIN/SUPPORTING role, no voice actor.
        var mangaExternal = anime with
        {
            Type = "manga",
            Title = "Berserk",
            OriginalTitle = "ベルセルク",
            Staff = [new ExternalStaffMemberDto("Kentaro Miura", "Story & Art", "https://s4.anilist.co/file/anilistcdn/staff/large/m1.jpg")],
            Cast = [new CastMemberDto("Guts", "Guts", "https://s4.anilist.co/file/anilistcdn/character/large/g1.jpg")
            {
                CharacterImageUrl = "https://s4.anilist.co/file/anilistcdn/character/large/g1.jpg",
                CharacterRole = "MAIN",
            }],
        };
        var manga = new Manga { Title = "Berserk" };
        MediaMetadataApplier
            .ApplyOverwriteAsync(manga, mangaExternal, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertEqual(failures, "ベルセルク", manga.OriginalTitle, "manga refresh stores the native title");
        var mangaCast = MediaJsonCache.Deserialize<CastMemberDto>(manga.CastJson);
        AssertEqual(failures, null, mangaCast.Single().VoiceActorName, "manga cast carries no voice actor");
        AssertEqual(failures, "MAIN", mangaCast.Single().CharacterRole, "manga cast keeps the character role");
        AssertEqual(failures, 1, MediaJsonCache.Deserialize<ExternalStaffMemberDto>(manga.StaffJson).Count, "manga stores its staff");

        // Enrich never wipes what the user already has.
        var enriched = mangaExternal with { Staff = [new ExternalStaffMemberDto("Other Guy", "Director", null)] };
        MediaMetadataApplier.ApplyIfMissing(manga, enriched);
        AssertEqual(failures, 1, MediaJsonCache.Deserialize<ExternalStaffMemberDto>(manga.StaffJson).Count, "enrich keeps the stored staff");
        AssertEqual(failures, "ベルセルク", manga.OriginalTitle, "enrich keeps the stored native title");
    }

    private static void CheckMergeCarriesCastAndTrailer(List<string> failures)
    {
        // Breaking Bad added from IMDb: the suggestion endpoint reports neither credits nor a video,
        // so both live on the TMDb answer that the cascade fetched second.
        var imdb = new ExternalMediaDto
        {
            ExternalId = "tt0903747",
            Title = "Breaking Bad",
            Type = "tvshow",
            Studio = "High Bridge Entertainment",
            TotalCount = 62,
            Description = "A chemistry teacher turns to manufacturing meth.",
            ReleaseYear = 2008,
            ReleaseDate = "2008-01-20",
        };
        var tmdb = new ExternalMediaDto
        {
            ExternalId = "1396",
            Title = "Breaking Bad",
            Type = "tvshow",
            TrailerVideoId = "HhesaQXLuRY",
            CreatorImageUrl = "https://image.tmdb.org/t/p/w185/studio.png",
            Cast =
            [
                new CastMemberDto("Bryan Cranston", "Walter White", "https://image.tmdb.org/t/p/w185/w185.jpg"),
                new CastMemberDto("Aaron Paul", "Jesse Pinkman", "https://image.tmdb.org/t/p/w185/paul.jpg")
            ],
        };

        var merged = MediaMerger.Merge(imdb, tmdb);

        AssertEqual(failures, "HhesaQXLuRY", merged.TrailerVideoId, "merge keeps a trailer the primary source lacks");
        AssertEqual(failures, 2, merged.Cast?.Count, "merge keeps the cast the primary source lacks");
        AssertEqual(
            failures,
            "https://image.tmdb.org/t/p/w185/studio.png",
            merged.CreatorImageUrl,
            "merge keeps the creator image the primary source lacks");

        // The reverse order must keep the photo-bearing list: the primary answer wins only because
        // names alone are worth less than faces in the overview.
        var namesOnly = imdb with { Cast = [new CastMemberDto("Bryan Cranston", "Walter White", null)] };
        AssertEqual(
            failures,
            2,
            MediaMerger.Merge(namesOnly, tmdb).Cast?.Count,
            "a cast list with photos beats one with names only"
        );
        AssertEqual(
            failures,
            2,
            MediaMerger.Merge(tmdb, namesOnly).Cast?.Count,
            "the photo-bearing primary cast survives a later merge"
        );

        // Without this the cascade treated the IMDb answer as complete and never asked for credits.
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(
                merged with { TrailerVideoId = null, Cast = null },
                "tvshow"),
            "a show without credits or a video keeps the cascade going"
        );
        AssertFalse(
            failures,
            MediaMerger.HasMissingMetadata(merged, "tvshow"),
            "a show with cast and a trailer stops the cascade"
        );
    }

    private static void CheckEnrichStoresGameDeveloper(List<string> failures)
    {
        var game = new VideoGame { Title = "PAYDAY 2", HoursPlayed = 34, Platform = "PC" };

        MediaMetadataApplier.ApplyIfMissing(
            game,
            new ExternalMediaDto
            {
                ExternalId = "rawg/1",
                Title = "PAYDAY 2",
                Type = "game",
                Platform = "PC",
                Studio = "Overkill Software",
            });

        AssertEqual(
            failures,
            "Overkill Software",
            game.Studio,
            "enrichment keeps the developer the overview's creator card shows"
        );
        AssertEqual(failures, 34, game.HoursPlayed, "the played hours survive enrichment");

        // A refresh may restate the developer, but a blank source must never wipe the known one.
        MediaMetadataApplier.ApplyIfMissing(game, new ExternalMediaDto { ExternalId = "rawg/1", Title = "PAYDAY 2", Type = "game" });
        AssertEqual(failures, "Overkill Software", game.Studio, "a source without a developer keeps the stored one");
    }

    private static void CheckMergeKeepsFinalChapterTotal(List<string> failures)
    {
        // Berserk: one source knows the finished run (386), the ongoing ones only know the latest
        // chapter or nothing at all. None of them may knock the real total back to a dash.
        var finished = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Berserk",
            Type = "manga",
            TotalCount = 386,
            Chapters = 386,
            Volumes = 41,
            ReleaseStatus = "finished",
        };
        var ongoingWithCount = new ExternalMediaDto
        {
            ExternalId = "2",
            Title = "Berserk",
            Type = "manga",
            TotalCount = 373,
            Chapters = 373,
            ReleaseStatus = "releasing",
        };
        var ongoingWithoutCount = new ExternalMediaDto
        {
            ExternalId = "3",
            Title = "Berserk",
            Type = "manga",
            Chapters = 364,
            ReleaseStatus = "releasing",
        };

        var mergedWithCount = MediaMerger.Merge(finished, ongoingWithCount);
        AssertEqual(
            failures,
            386,
            mergedWithCount.TotalCount,
            "merge keeps the final chapter total over a lower ongoing one"
        );
        AssertEqual(
            failures,
            386,
            mergedWithCount.Chapters,
            "merge keeps the final chapter count over a lower ongoing one"
        );

        var mergedWithNone = MediaMerger.Merge(ongoingWithoutCount, finished);
        AssertEqual(
            failures,
            386,
            mergedWithNone.TotalCount,
            "merge fills the total from the other source when the first knows none"
        );

        var unknown = MediaMerger.Merge(
            ongoingWithoutCount with { TotalCount = null, Chapters = null },
            ongoingWithCount with { TotalCount = null, Chapters = null, Volumes = null });
        AssertEqual(
            failures,
            null,
            unknown.TotalCount,
            "merge reports no total only when no source knows one"
        );

        var fromChapters = MediaMerger.Merge(
            ongoingWithoutCount with { TotalCount = null },
            ongoingWithCount with { TotalCount = null, Chapters = null });
        AssertEqual(
            failures,
            364,
            fromChapters.TotalCount,
            "merge falls back to a known chapter count when no total is reported"
        );
    }

    /// <summary>
    /// Related metadata has to survive a round trip through storage.
    /// </summary>
    private static void CheckRelatedMediaSurvivesRoundTrip(List<string> failures)
    {
        var item = new Manga { Title = "Noragami" };

        MediaItemUpdater.Apply(item, new UpdateMediaRequest());
        AssertEqual(
            failures,
            null,
            item.RelatedMediaJson,
            "an update without the related payload leaves the cache alone"
        );

        MediaItemUpdater.Apply(
            item,
            new UpdateMediaRequest { RelatedMediaJson = "[{\"id\":\"7\"}]", RelatedSource = "MangaDex" });

        AssertEqual(
            failures,
            "[{\"id\":\"7\"}]",
            item.RelatedMediaJson,
            "the related payload is stored on the entity"
        );
        AssertEqual(failures, "MangaDex", item.RelatedSource, "the related source is stored on the entity");

        var dto = MediaResponseMapper.ToDetailDto(item);
        AssertEqual(
            failures,
            "[{\"id\":\"7\"}]",
            dto.RelatedMediaJson,
            "the detail payload carries the cached related titles"
        );
        AssertEqual(failures, "MangaDex", dto.RelatedSource, "the detail payload carries the related source");
    }

    private static void CheckMissingMetadataDrivesCascade(List<string> failures)
    {
        var complete = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Дюна",
            Type = "movie",
            Description = "Desert planet",
            ReleaseYear = 2021,
            ReleaseDate = "2021-10-22",
            RuntimeMinutes = 155,
            Studio = "Legendary Pictures",
            TrailerVideoId = "Way9Dexny3w",
            Cast = [new CastMemberDto("Timothée Chalamet", "Paul Atreides", null)],
        };
        AssertFalse(
            failures,
            MediaMerger.HasMissingMetadata(complete, "movie"),
            "a complete movie stops the cascade"
        );

        // Runtime and studio must count as gaps: this is what makes the aggregator ask the next source.
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(complete with { RuntimeMinutes = null }, "movie"),
            "a missing runtime keeps the cascade going"
        );
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(complete with { Studio = null }, "movie"),
            "a missing studio keeps the cascade going"
        );

        // Year alone is not a date: a source that only knows the year must be asked as well.
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(complete with { ReleaseDate = null }, "movie"),
            "a missing release date keeps the cascade going"
        );

        // Credits and a video are what the overview renders, so they count as gaps too.
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(complete with { Cast = null }, "movie"),
            "a movie without cast keeps the cascade going"
        );
        AssertTrue(
            failures,
            MediaMerger.HasMissingMetadata(complete with { TrailerVideoId = null }, "movie"),
            "a movie without a trailer keeps the cascade going"
        );
    }

    private static void CheckPartialDatesDoNotBecomeJanFirst(List<string> failures)
    {
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Дюна",
            Type = "movie",
            ReleaseYear = 2021,
            ReleaseDate = "2021",
        };

        var yearOnly = new Movie { Title = "Дюна" };
        MediaMetadataApplier
            .ApplyOverwriteAsync(yearOnly, external, new NullImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertTrue(
            failures,
            yearOnly.ReleaseDate is null,
            "a year-only source must not become 1 January"
        );
        AssertEqual(failures, 2021, yearOnly.ReleaseYear, "the year is kept as a year");

        var full = new Movie { Title = "Дюна" };
        MediaMetadataApplier
            .ApplyOverwriteAsync(
                full,
                external with
                {
                    ReleaseDate = "2021-10-22",
                },
                new NullImageStorage(),
                CancellationToken.None
            )
            .GetAwaiter()
            .GetResult();

        AssertEqual(
            failures,
            new DateTime(2021, 10, 22),
            full.ReleaseDate,
            "a full date is stored as-is"
        );
    }

    /// <summary>
    /// A movie must never reach the "TV Shows" group: Kinopoisk answers a keyword search with films
    /// and series mixed together, so every item is checked against the declared type.
    /// </summary>
    private static void CheckSearchTypeFiltering(List<string> failures)
    {
        AssertFalse(
            failures,
            KinopoiskMetadataProvider.MatchesType("movie", "tv"),
            "a film is not a series result"
        );
        AssertFalse(
            failures,
            KinopoiskMetadataProvider.MatchesType("tv-series", "movie"),
            "a series is not a movie result"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("tv-series", "tv"),
            "a series belongs to the tv group"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("movie", "movie"),
            "a film belongs to the movie group"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType(null, "tv"),
            "an unclassified item is kept rather than hidden"
        );
    }

    /// <summary>ApplyOverwriteAsync only reaches the cover through this seam; the checks pass none.</summary>
    private sealed class NullImageStorage : IImageStorageService
    {
        public Task<string?> SaveCoverAsync(string url, Guid mediaId, CancellationToken ct, string folder = "cover") =>
            Task.FromResult<string?>(null);

        public void DeleteCover(string? path) { }

        public void DeleteMediaFolder(Guid mediaId) { }
    }

    private static void CheckMangaFormatFromSources(List<string> failures)
    {
        AssertEqual(
            failures,
            MangaFormats.Manhwa,
            MangaFormats.FromCountryOfOrigin("KR"),
            "AniList KR is manhwa"
        );
        AssertEqual(
            failures,
            MangaFormats.Manhua,
            MangaFormats.FromCountryOfOrigin("CN"),
            "AniList CN is manhua"
        );
        AssertEqual(
            failures,
            MangaFormats.Manga,
            MangaFormats.FromCountryOfOrigin("JP"),
            "AniList JP is manga"
        );
        AssertEqual(
            failures,
            null,
            MangaFormats.FromCountryOfOrigin("US"),
            "unknown country yields nothing"
        );

        // The OEL signal only exists in MangaDex's original language; AniList files these under JP.
        AssertEqual(
            failures,
            MangaFormats.Oel,
            MangaFormats.FromOriginalLanguage("en"),
            "MangaDex en is OEL"
        );
        AssertEqual(
            failures,
            MangaFormats.Manhwa,
            MangaFormats.FromOriginalLanguage("ko"),
            "MangaDex ko is manhwa"
        );
        AssertEqual(
            failures,
            MangaFormats.Manhua,
            MangaFormats.FromOriginalLanguage("zh"),
            "MangaDex zh is manhua"
        );
        AssertEqual(
            failures,
            MangaFormats.Manga,
            MangaFormats.FromOriginalLanguage("ja"),
            "MangaDex ja is manga"
        );
        AssertEqual(
            failures,
            null,
            MangaFormats.FromOriginalLanguage(null),
            "missing language yields nothing"
        );

        var manga = new Manga { Title = "Solo Leveling" };
        MediaMetadataApplier.ApplyIfMissing(
            manga,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Solo Leveling",
                Type = "manga",
                MangaFormat = MangaFormats.Manhwa,
            }
        );
        AssertEqual(
            failures,
            MangaFormats.Manhwa,
            manga.Format,
            "manga format stored from external"
        );
    }

    private static void CheckMangaFormatMergePrefersOel(List<string> failures)
    {
        // AniList says "manga", MangaDex knows it is original English: the specific answer must win,
        // otherwise every OEL title silently reads as plain manga.
        var merged = MediaMerger.Merge(
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "SubZero",
                Type = "manga",
                MangaFormat = MangaFormats.Manga,
            },
            new ExternalMediaDto
            {
                ExternalId = "2",
                Title = "SubZero",
                Type = "manga",
                MangaFormat = MangaFormats.Oel,
            }
        );
        AssertEqual(
            failures,
            MangaFormats.Oel,
            merged.MangaFormat,
            "OEL from the second source wins"
        );

        var primaryWins = MediaMerger.Merge(
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Tower of God",
                Type = "manga",
                MangaFormat = MangaFormats.Manhwa,
            },
            new ExternalMediaDto
            {
                ExternalId = "2",
                Title = "Tower of God",
                Type = "manga",
                MangaFormat = MangaFormats.Manga,
            }
        );
        AssertEqual(
            failures,
            MangaFormats.Manhwa,
            primaryWins.MangaFormat,
            "primary source wins when no OEL"
        );

        var filled = MediaMerger.Merge(
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Berserk",
                Type = "manga",
            },
            new ExternalMediaDto
            {
                ExternalId = "2",
                Title = "Berserk",
                Type = "manga",
                MangaFormat = MangaFormats.Manga,
            }
        );
        AssertEqual(
            failures,
            MangaFormats.Manga,
            filled.MangaFormat,
            "format falls back to the second source"
        );
    }

    private static void CheckMangaGapEnrichment(List<string> failures)
    {
        var manga = new Manga { Title = "Berserk" };
        manga.Volumes.Add(
            new MangaVolume
            {
                Title = "Volume 1",
                VolumeNumber = 1,
                TotalChapters = 0,
            }
        );
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Berserk",
            Type = "manga",
            Chapters = 374,
            Volumes = 41,
            Author = "Kentaro Miura",
        };

        var modified = MediaMetadataApplier.ApplyIfMissing(manga, external);

        AssertTrue(failures, modified, "enrich reports a change");
        AssertEqual(failures, 374, manga.TotalChapters, "manga chapters filled");
        AssertEqual(failures, 41, manga.TotalVolumes, "manga volumes filled");
        AssertEqual(failures, "Kentaro Miura", manga.Author, "manga author filled");

        // A flat total says nothing about which volume a chapter belongs to, so it must not be
        // pushed onto the one existing volume: that is the invented split this used to produce.
        // The per-volume number comes from MangaDex's /aggregate, never from the series total.
        AssertEqual(
            failures,
            0,
            manga.Volumes[0].TotalChapters,
            "a flat chapter total is not spread onto a volume"
        );
    }

    private static void CheckMangaGapEnrichmentDoesNotOverwrite(List<string> failures)
    {
        var manga = new Manga
        {
            Title = "Berserk",
            TotalChapters = 100,
            Author = "User typed this",
            Notes = "My reading notes",
        };
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Berserk",
            Type = "manga",
            Chapters = 374,
            Author = "Kentaro Miura",
            Description = "A dark fantasy epic",
        };

        MediaMetadataApplier.ApplyIfMissing(manga, external);

        AssertEqual(failures, 100, manga.TotalChapters, "enrich must not overwrite a user value");
        AssertEqual(
            failures,
            "User typed this",
            manga.Author,
            "enrich must not overwrite a user author"
        );
        AssertEqual(failures, "A dark fantasy epic", manga.Description, "enrich fills empty description");
        AssertEqual(failures, "My reading notes", manga.Notes, "enrich preserves personal notes");
    }

    private static void CheckOverwriteRefresh(List<string> failures)
    {
        var book = new Book
        {
            Title = "Old title",
            Author = string.Empty,
            TotalPages = 100,
            CurrentPage = 50,
            Notes = "My private note",
            Description = "Old synopsis",
        };
        var external = new ExternalMediaDto
        {
            ExternalId = "42",
            Title = "New title",
            Type = "book",
            TotalCount = 321,
            Author = "Someone Else",
            Description = "Fresh synopsis",
            TrailerVideoId = "abc123",
            CreatorImageUrl = "https://image.tmdb.org/t/p/w185/author.jpg",
        };

        MediaMetadataApplier
            .ApplyOverwriteAsync(book, external, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertEqual(failures, "New title", book.Title, "refresh overwrites the title");
        AssertEqual(failures, 321, book.TotalPages, "refresh overwrites the page count");
        AssertEqual(failures, "Someone Else", book.Author, "refresh overwrites the author");
        AssertEqual(failures, "Fresh synopsis", book.Description, "refresh overwrites the description");
        AssertEqual(failures, "My private note", book.Notes, "refresh preserves personal notes");
        AssertEqual(failures, "abc123", book.TrailerVideoId, "refresh stores the trailer id");
        AssertEqual(
            failures,
            "https://image.tmdb.org/t/p/w185/author.jpg",
            book.CreatorImageUrl,
            "refresh stores the creator image");

        // A source without a photo must not erase the one already on the row: the UI falls back to a
        // role icon, and a blank out would leave a saved file nothing points at.
        MediaMetadataApplier
            .ApplyOverwriteAsync(book, external with { CreatorImageUrl = null }, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertEqual(
            failures,
            "https://image.tmdb.org/t/p/w185/author.jpg",
            book.CreatorImageUrl,
            "refresh keeps a creator image the new source does not have");
    }

    /// <summary>
    /// The season and volume steppers now write through ExecuteUpdateAsync with no tracked entity,
    /// so their status rules moved out of the endpoints. These assertions pin that behaviour.
    /// </summary>
    private static void CheckSeasonProgressStepper(List<string> failures)
    {
        AssertEqual(
            failures,
            12,
            ProgressStepperRules.Clamp(12, 12),
            "episode clamps to the total"
        );
        AssertEqual(
            failures,
            0,
            ProgressStepperRules.Clamp(-5, 12),
            "negative progress floors at zero"
        );
        AssertEqual(
            failures,
            999,
            ProgressStepperRules.Clamp(999, 0),
            "an unknown total does not clamp"
        );

        AssertEqual(
            failures,
            MediaStatus.Completed,
            ProgressStepperRules.ResolveEpisodeStatus(12, 12),
            "last episode completes"
        );
        AssertEqual(
            failures,
            MediaStatus.InProgress,
            ProgressStepperRules.ResolveEpisodeStatus(5, 12),
            "partial episode is in progress"
        );
        AssertEqual(
            failures,
            MediaStatus.Planned,
            ProgressStepperRules.ResolveEpisodeStatus(0, 12),
            "no episodes is planned"
        );

        var started = new DateTime(2026, 1, 1);
        var now = new DateTime(2026, 2, 2);

        var allDone = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.InProgress,
            started,
            null,
            allCompleted: true,
            anyWatched: true,
            now
        );
        AssertEqual(
            failures,
            MediaStatus.Completed,
            allDone.Status,
            "all seasons done completes the show"
        );
        AssertEqual(failures, started, allDone.StartedAt, "existing start date is kept");
        AssertEqual(failures, now, allDone.FinishedAt, "completing stamps a finish date");

        var partly = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.Planned,
            null,
            null,
            allCompleted: false,
            anyWatched: true,
            now
        );
        AssertEqual(
            failures,
            MediaStatus.InProgress,
            partly.Status,
            "a watched season moves a planned show to in progress"
        );
        AssertEqual(failures, now, partly.StartedAt, "starting stamps the start date");

        var rewound = ProgressStepperRules.ResolveShowStatus(
            MediaStatus.Completed,
            started,
            now,
            allCompleted: false,
            anyWatched: false,
            now
        );
        AssertEqual(
            failures,
            MediaStatus.Planned,
            rewound.Status,
            "rewinding to zero returns the show to planned"
        );
        AssertEqual(failures, null, rewound.StartedAt, "rewinding clears the start date");
        AssertEqual(failures, null, rewound.FinishedAt, "rewinding clears the finish date");
    }

    private static void CheckStatusTransitions(List<string> failures)
    {
        var show = new TvShow { Title = "Frieren" };
        show.Seasons.Add(
            new TvSeason
            {
                Title = "Season 1",
                SeasonNumber = 1,
                TotalEpisodes = 12,
                CurrentEpisode = 4,
            }
        );

        MediaStatusTransitions.Apply(show, MediaStatus.Completed);
        AssertEqual(
            failures,
            12,
            show.Seasons[0].CurrentEpisode,
            "completing a show finishes the season"
        );
        AssertEqual(
            failures,
            MediaStatus.Completed,
            show.Seasons[0].Status,
            "completing a show completes the season"
        );

        var planned = new Book
        {
            Title = "Dune",
            Author = string.Empty,
            TotalPages = 412,
            CurrentPage = 300,
            StartedAt = DateTime.UtcNow,
        };
        MediaStatusTransitions.Apply(planned, MediaStatus.Planned);
        AssertEqual(
            failures,
            null,
            planned.StartedAt,
            "moving back to planned clears the start date"
        );
        AssertEqual(
            failures,
            0,
            planned.CurrentPage,
            "moving to planned clears the phantom progress"
        );

        var plannedShow = new TvShow { Title = "Naruto" };
        plannedShow.Seasons.Add(
            new TvSeason
            {
                Title = "Season 1",
                SeasonNumber = 1,
                TotalEpisodes = 220,
                CurrentEpisode = 220,
                Status = MediaStatus.Completed,
            }
        );
        MediaStatusTransitions.Apply(plannedShow, MediaStatus.Planned);
        AssertEqual(
            failures,
            0,
            plannedShow.TotalEpisodesWatched,
            "a planned show watches no episodes"
        );
        AssertEqual(
            failures,
            MediaStatus.Planned,
            plannedShow.Seasons[0].Status,
            "a planned show has planned seasons"
        );
    }

    /// <summary>
    /// A manga must never gain volumes out of a local guess. Creating a series used to seed one stub
    /// per requested volume and divide the chapter budget evenly between them, which is fabricated
    /// data: only MangaDex knows how many chapters a volume actually holds.
    /// </summary>
    private static void CheckNoInventedVolumes(List<string> failures)
    {
        var request = new CreateMediaRequest
        {
            Type = "manga",
            Title = "Naruto",
            TotalChapters = 700,
            TotalVolumes = 4,
        };
        var manga = new Manga { Title = "Naruto", TotalChapters = 700 };

        MediaMetadataApplier.ApplyIfMissing(
            manga,
            new ExternalMediaDto
            {
                ExternalId = "shikimori/1",
                ExternalSource = "Shikimori",
                Title = "Naruto",
                Type = "manga",
                TotalCount = 700,
                Chapters = 700,
            });

        AssertEqual(
            failures,
            0,
            manga.Volumes.Count,
            "a source without a volume breakdown leaves the volumes empty"
        );
        AssertEqual(failures, 700, manga.TotalChapters, "the flat chapter total is still kept");
    }

    private static void CheckReleaseStatusComputation(List<string> failures)
    {
        var today = DateTime.UtcNow.Date;

        AssertEqual(
            failures,
            "NOT_YET_RELEASED",
            MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(30), null),
            "future release"
        );
        AssertEqual(
            failures,
            "RELEASING",
            MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(-30), null),
            "ongoing release"
        );
        AssertEqual(
            failures,
            "FINISHED",
            MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(-300), today.AddDays(-1)),
            "ended release"
        );
        AssertEqual(
            failures,
            null,
            MediaItemFactory.ComputeReleaseStatusFromDates(null, null),
            "unknown release"
        );
    }

    /// <summary>
    /// A chunked cover response declares no Content-Length, so the byte cap has to hold on its own.
    /// </summary>
    private static void CheckCoverSizeLimit(List<string> failures)
    {
        using var withinLimit = new SizeLimitedStream(new MemoryStream(new byte[64]), 128);
        AssertEqual(
            failures,
            64,
            withinLimit.Read(new byte[128]),
            "stream passes through a body under the limit"
        );

        using var overLimit = new SizeLimitedStream(new MemoryStream(new byte[512]), 128);
        var threw = false;
        try
        {
            while (overLimit.Read(new byte[128]) > 0) { }
        }
        catch (OversizedCoverException)
        {
            threw = true;
        }

        AssertTrue(failures, threw, "stream rejects a body past the limit");
    }

    /// <summary>
    /// The built-in provider keys resolve without lowercasing the id first, so the case-insensitive
    /// comparison is the only thing keeping "TMDB" working.
    /// </summary>
    private static void CheckApiKeyLookup(List<string> failures)
    {
        var options = new ExternalApiOptions();

        options.SetKey("TMDB", "tmdb-secret");
        options.SetKey("TheTVDB", "tvdb-secret");
        options.SetKey("steam", "steam-secret");
        options.SetKey("SomeCustomProvider", "custom-secret");

        AssertEqual(failures, "tmdb-secret", options.GetKey("tmdb"), "built-in key stored");
        AssertEqual(
            failures,
            "tmdb-secret",
            options.GetKey("TMDB"),
            "built-in key resolves regardless of case"
        );
        AssertEqual(
            failures,
            "tvdb-secret",
            options.GetKey("thetvdb"),
            "alias resolves to the same slot"
        );
        AssertEqual(failures, "steam-secret", options.GetKey("steam"), "Steam key stored");
        AssertEqual(
            failures,
            "custom-secret",
            options.GetKey("SomeCustomProvider"),
            "custom key resolves regardless of case"
        );
        AssertEqual(failures, null, options.GetKey("unknown"), "unknown provider has no key");

        options.SetKey(" igdb ", "igdb-secret");
        AssertEqual(
            failures,
            "igdb-secret",
            options.GetKey("igdb"),
            "surrounding whitespace is trimmed"
        );
    }

    private static void CheckCommandLineParsing(List<string> failures)
    {
        AssertEqual(
            failures,
            null,
            CommandLineOptions.Parse([]).Error,
            "no arguments is not an error"
        );
        AssertEqual(
            failures,
            CommandLineOptions.DefaultServerUrl,
            CommandLineOptions.Parse([]).ServerUrl,
            "default server url"
        );
        AssertEqual(
            failures,
            true,
            CommandLineOptions.Parse(["--headless"]).IsHeadless,
            "--headless"
        );
        AssertEqual(
            failures,
            true,
            CommandLineOptions.Parse(["--server-only"]).IsHeadless,
            "--server-only alias"
        );
        AssertEqual(
            failures,
            TsundokuRunMode.GuiOnly,
            CommandLineOptions.Parse(["--gui"]).Mode,
            "--gui"
        );
        AssertEqual(
            failures,
            TsundokuRunMode.GuiOnly,
            CommandLineOptions.Parse(["--client-only"]).Mode,
            "--client-only alias"
        );

        var portOnly = CommandLineOptions.Parse(["--port", "5050"]);
        AssertEqual(failures, 5050, portOnly.Port, "--port value");
        AssertEqual(
            failures,
            "http://127.0.0.1:5050",
            portOnly.ServerUrl,
            "--port moves the default server url"
        );
        AssertEqual(failures, 5050, CommandLineOptions.Parse(["-p", "5050"]).Port, "-p alias");

        var remote = CommandLineOptions.Parse([
            "--gui",
            "--server-url",
            "http://192.168.1.50:5000/",
        ]);
        AssertEqual(
            failures,
            "http://192.168.1.50:5000",
            remote.ServerUrl,
            "--server-url trailing slash is trimmed"
        );

        AssertEqual(
            failures,
            "D:\\TsundokuData",
            CommandLineOptions.Parse(["--data-dir", "D:\\TsundokuData"]).DataDirectory,
            "--data-dir"
        );
        AssertEqual(
            failures,
            true,
            CommandLineOptions.Parse(["--migrate-only"]).MigrateOnly,
            "--migrate-only"
        );
        AssertEqual(failures, true, CommandLineOptions.Parse(["--help"]).ShowHelp, "--help");
        AssertEqual(failures, true, CommandLineOptions.Parse(["-h"]).ShowHelp, "-h alias");

        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--port", "abc"]).Error is not null,
            "non-numeric port rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--port", "70000"]).Error is not null,
            "out-of-range port rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--port"]).Error is not null,
            "port without a value rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--server-url", "not-a-url"]).Error is not null,
            "relative server url rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--server-url"]).Error is not null,
            "server url without a value rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--data-dir"]).Error is not null,
            "data dir without a value rejected"
        );
        AssertTrue(
            failures,
            CommandLineOptions.Parse(["--nope"]).Error is not null,
            "unknown option rejected"
        );
    }

    /// <summary>
    /// The source reports no start/end date on the film, only years, so the show's real bounds come
    /// from the first and last episode air date. This is the whole reason a Kinopoisk series shows
    /// "12 янв. 2015" instead of a bare year.
    /// </summary>
    private static void CheckKinopoiskAirDateRange(List<string> failures)
    {
        var episodes = new List<ExternalEpisodeDto>
        {
            new() { Number = 1, Title = "Пилот", AirDate = "2015-01-12" },
            new() { Number = 2, Title = "Второй", AirDate = "2015-01-19" },
            new() { Number = 3, Title = "Финал", AirDate = "2019-05-06" },
        };

        var (start, end) = KinopoiskMetadataProvider.ResolveAirDateRange(episodes);
        AssertEqual(failures, "2015-01-12", start, "start is the earliest episode air date");
        AssertEqual(failures, "2019-05-06", end, "end is the latest episode air date");

        // A movie has no episodes, so the dates stay unset and the cascade asks the other sources
        // instead of storing a fabricated January 1st.
        var (noStart, noEnd) = KinopoiskMetadataProvider.ResolveAirDateRange([]);
        AssertEqual(failures, null, noStart, "no episodes means no start date");
        AssertEqual(failures, null, noEnd, "no episodes means no end date");

        // An unparseable air date must not be turned into a date.
        var (partial, _) = KinopoiskMetadataProvider.ResolveAirDateRange(
            [new ExternalEpisodeDto { Number = 1, Title = "Пилот", AirDate = "неизвестно" }]
        );
        AssertEqual(failures, null, partial, "an unparseable air date is not a date");
    }

    private static void CheckEnrichFillsEndDateAndStatus(List<string> failures)
    {
        var show = new TvShow { Title = "Шоу" };
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Шоу",
            Type = "tvshow",
            ReleaseDate = "2015-01-12",
            EndDate = "2019-05-06",
            TotalCount = 62,
        };

        AssertTrue(
            failures,
            MediaMetadataApplier.ApplyIfMissing(show, external),
            "enrich reports a change for a show with dates"
        );
        AssertEqual(
            failures,
            new DateTime(2019, 5, 6),
            show.EndDate,
            "enrich fills the end date (Дата окончания)"
        );
        // No source declared a status, but a past end date decides it.
        AssertEqual(
            failures,
            "FINISHED",
            show.ReleaseStatus,
            "enrich derives the status from the dates it just filled"
        );

        // An ongoing series has no end date and must not inherit a bogus FINISHED.
        var ongoing = new TvShow { Title = "Онгоинг" };
        MediaMetadataApplier.ApplyIfMissing(
            ongoing,
            new ExternalMediaDto
            {
                ExternalId = "2",
                Title = "Онгоинг",
                Type = "tvshow",
                ReleaseDate = "2020-01-10",
            }
        );
        AssertEqual(
            failures,
            "RELEASING",
            ongoing.ReleaseStatus,
            "a past start date with no end date reads as releasing"
        );
        AssertEqual(failures, null, ongoing.EndDate, "an ongoing show keeps a null end date");
    }

    /// <summary>
    /// Episodes used to be written for anime only, so every live-action series lost its per-episode
    /// air dates — which is where the start/end dates for a show come from.
    /// </summary>
    private static void CheckEnrichStoresEpisodesForLiveAction(List<string> failures)
    {
        var show = new TvShow { Title = "Шоу", IsAnime = false };
        MediaMetadataApplier.ApplyIfMissing(
            show,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Шоу",
                Type = "tvshow",
                TotalCount = 2,
                Episodes =
                [
                    new ExternalEpisodeDto { Number = 1, Title = "Пилот", AirDate = "2015-01-12" },
                    new ExternalEpisodeDto { Number = 2, Title = "Второй", AirDate = "2015-01-19" },
                ],
            }
        );

        AssertEqual(
            failures,
            1,
            show.Seasons.Count,
            "a live-action show gets its season created"
        );
        AssertEqual(
            failures,
            2,
            show.Seasons[0].TotalEpisodes,
            "the season carries the episode count"
        );

        var stored = JsonSerializer.Deserialize<List<ExternalEpisodeDto>>(
            show.Seasons[0].EpisodesData ?? "[]",
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
        );
        AssertEqual(failures, 2, stored?.Count ?? 0, "both episodes are stored");
        AssertEqual(
            failures,
            "2015-01-12",
            stored?[0].AirDate,
            "the first episode keeps its air date"
        );
    }

    /// <summary>
    /// TMDb reports an episode count but no per-episode rows, and the count is only ever persisted on
    /// a season — so without a season the "62 серии" row stayed at 0.
    /// </summary>
    private static void CheckRealSeasonsCreateOneTvSeasonEach(List<string> failures)
    {
        var show = new TvShow { Title = "Во все тяжкие" };

        MediaMetadataApplier.ApplyIfMissing(
            show,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Во все тяжкие",
                Type = "tvshow",
                TotalCount = 62,
                Seasons =
                [
                    Season(1, 7),
                    Season(2, 13),
                    Season(3, 13),
                    Season(4, 13),
                    Season(5, 16),
                ],
            }
        );

        AssertEqual(failures, 5, show.Seasons.Count, "one TvSeason per reported season");
        AssertEqual(failures, 62, show.TotalEpisodesCount, "the episodes are not lost");
        AssertEqual(failures, 7, show.Seasons[0].TotalEpisodes, "season 1 keeps its own length");
        AssertEqual(failures, 16, show.Seasons[4].TotalEpisodes, "season 5 keeps its own length");
        AssertEqual(failures, 5, show.Seasons[4].SeasonNumber, "season numbers are preserved");
        AssertEqual(
            failures,
            3,
            show.Seasons.Count(s => s.TotalEpisodes == 13),
            "three seasons have 13 episodes each"
        );

        // A refresh must update the rows it already has rather than appending a second copy.
        MediaMetadataApplier.ApplyIfMissing(
            show,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Во все тяжкие",
                Type = "tvshow",
                TotalCount = 62,
                Seasons = [Season(1, 7), Season(2, 13), Season(3, 13), Season(4, 13), Season(5, 16)],
            }
        );

        AssertEqual(failures, 5, show.Seasons.Count, "a refresh does not duplicate seasons");
    }

    private static ExternalSeasonDto Season(int number, int episodeCount) =>
        new()
        {
            Number = number,
            Title = $"Season {number}",
            TotalEpisodes = episodeCount,
            Episodes =
            [
                .. Enumerable.Range(1, episodeCount).Select(index => new ExternalEpisodeDto
                {
                    Number = index,
                    Title = $"Episode {index}",
                    AirDate = null,
                })
            ],
        };

    /// <summary>
    /// Disabling a source has to remove its badge. Refresh only ever rewrites the rows the queried
    /// source reported, so without this the badge survived every later refresh.
    /// </summary>
    private static void CheckRefreshDropsRatingsOfDisabledSources(List<string> failures)
    {
        var item = new Movie { Title = "Дюна" };
        MediaMetadataApplier.ApplyRatings(
            item,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Дюна",
                Type = "movie",
                Rating = 8.1,
                Ratings =
                [
                    new ExternalRatingDto { Source = "Kinopoisk", Rating = 8.1, Votes = 500 },
                    new ExternalRatingDto { Source = "IMDb", Rating = 8.0, Votes = 9000 },
                ],
            }
        );

        var disabled = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "kinopoisk" };

        AssertTrue(
            failures,
            MediaMetadataApplier.RemoveDisabledRatings(item, disabled),
            "removing a disabled source reports a change"
        );
        AssertFalse(
            failures,
            (item.ExternalRatingsJson ?? "").Contains("Kinopoisk", StringComparison.OrdinalIgnoreCase),
            "the disabled source's badge is gone"
        );
        AssertTrue(
            failures,
            (item.ExternalRatingsJson ?? "").Contains("IMDb", StringComparison.Ordinal),
            "the still-enabled source keeps its badge"
        );

        // Idempotent: a second pass must not report a change or wipe the payload.
        AssertFalse(
            failures,
            MediaMetadataApplier.RemoveDisabledRatings(item, disabled),
            "a second pass is a no-op"
        );

        // Disabling the last source clears the payload instead of leaving "[ ]" behind.
        var onlyImdb = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "imdb" };
        AssertTrue(
            failures,
            MediaMetadataApplier.RemoveDisabledRatings(item, onlyImdb),
            "disabling the last source reports a change"
        );
        AssertEqual(failures, null, item.ExternalRatingsJson, "an empty rating list stores null");
        AssertEqual(failures, null, item.ExternalRating, "the scalar rating goes with it");
    }

    private static void CheckEnrichStoresEpisodeCountWithoutEpisodes(List<string> failures)
    {
        var show = new TvShow { Title = "Шоу" };
        MediaMetadataApplier.ApplyIfMissing(
            show,
            new ExternalMediaDto
            {
                ExternalId = "1",
                Title = "Шоу",
                Type = "tvshow",
                TotalCount = 62,
            }
        );

        AssertEqual(failures, 1, show.Seasons.Count, "a count-only source still gets a season");
        AssertEqual(failures, 62, show.Seasons[0].TotalEpisodes, "the count reaches the season");
        AssertEqual(
            failures,
            null,
            show.Seasons[0].EpisodesData,
            "no invented per-episode rows"
        );
    }

    /// <summary>
    /// The source labels titles with UPPER_SNAKE enums (FILM / TV_SERIES / ...). The old comparison
    /// only knew "movie" / "tv-series", so nothing ever matched and every result was cross-listed.
    /// </summary>
    private static void CheckKinopoiskEnumMapping(List<string> failures)
    {
        AssertTrue(failures, KinopoiskMetadataProvider.MatchesType("FILM", "movie"), "FILM is a movie");
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("VIDEO", "movie"),
            "VIDEO is a movie"
        );
        AssertFalse(
            failures,
            KinopoiskMetadataProvider.MatchesType("TV_SERIES", "movie"),
            "TV_SERIES is not a movie"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("TV_SERIES", "tv"),
            "TV_SERIES belongs to the tv group"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("MINI_SERIES", "tv"),
            "MINI_SERIES belongs to the tv group"
        );
        AssertTrue(
            failures,
            KinopoiskMetadataProvider.MatchesType("TV_SHOW", "tv"),
            "TV_SHOW belongs to the tv group"
        );
        AssertFalse(
            failures,
            KinopoiskMetadataProvider.MatchesType("FILM", "tv"),
            "FILM is not a tv result"
        );

        AssertEqual(
            failures,
            "FINISHED",
            KinopoiskMetadataProvider.MapReleaseStatus("COMPLETED"),
            "COMPLETED maps to finished"
        );
        AssertEqual(
            failures,
            "RELEASING",
            KinopoiskMetadataProvider.MapReleaseStatus("FILMING"),
            "FILMING maps to releasing"
        );
        AssertEqual(
            failures,
            "RELEASING",
            KinopoiskMetadataProvider.MapReleaseStatus("post_production"),
            "POST_PRODUCTION maps to releasing, case-insensitively"
        );
        AssertEqual(
            failures,
            "NOT_YET_RELEASED",
            KinopoiskMetadataProvider.MapReleaseStatus("ANNOUNCED"),
            "ANNOUNCED maps to not yet released"
        );
        AssertEqual(
            failures,
            null,
            KinopoiskMetadataProvider.MapReleaseStatus("UNKNOWN"),
            "UNKNOWN is dropped so the dates can decide"
        );
    }

    private static void CheckKinopoiskEndDateOnlyWhenFinished(List<string> failures)
    {
        AssertEqual(
            failures,
            "2019-05-06",
            KinopoiskMetadataProvider.ResolveEndDate(true, "COMPLETED", "2019-05-06"),
            "a completed show keeps its last air date as the end date"
        );
        AssertEqual(
            failures,
            null,
            KinopoiskMetadataProvider.ResolveEndDate(false, "FILMING", "2024-03-01"),
            "a still-airing show reports no end date"
        );
        AssertEqual(
            failures,
            null,
            KinopoiskMetadataProvider.ResolveEndDate(null, null, "2024-03-01"),
            "an unflagged show reports no end date"
        );
    }

    /// <summary>
    /// The production SQLite tuning, applied to a real database file and read back. These pragmas are
    /// the difference between a responsive library screen and one that blocks on every write, so the
    /// effective values are measured rather than trusted to a string literal.
    /// </summary>
    private static void CheckSqliteTuningIsPreserved(List<string> failures)
    {
        var script = SqliteConnectionInterceptor.BuildPragmaScript();

        AssertTrue(
            failures,
            script.Contains("journal_mode = WAL", StringComparison.Ordinal),
            "the first connection open enables WAL");

        // journal_mode is a property of the file, so it must be applied once and then dropped.
        var subsequent = SqliteConnectionInterceptor.BuildPragmaScript();
        AssertFalse(
            failures,
            subsequent.Contains("journal_mode", StringComparison.Ordinal),
            "the journal pragma is not re-sent on later connections");

        var databasePath = Path.Combine(Path.GetTempPath(), $"tsundoku_selfcheck_{Guid.NewGuid():N}.db");

        try
        {
            using var connection = new SqliteConnection($"Data Source={databasePath}");
            connection.Open();

            using (var open = connection.CreateCommand())
            {
                open.CommandText = script;
                open.ExecuteNonQuery();
            }

            AssertEqual(failures, "wal", ReadTextPragma(connection, "journal_mode"), "journal_mode is WAL");
            AssertEqual(failures, "1", ReadTextPragma(connection, "synchronous"), "synchronous is NORMAL (1)");
            AssertEqual(failures, "5000", ReadTextPragma(connection, "busy_timeout"), "busy_timeout is 5000 ms");
            AssertEqual(failures, "-64000", ReadTextPragma(connection, "cache_size"), "cache_size is -64000");
        }
        catch (Exception ex)
        {
            failures.Add($"sqlite tuning could not be applied to a real database: {ex.Message}");
        }
        finally
        {
            TryDelete(databasePath);
        }
    }

    private static string ReadTextPragma(SqliteConnection connection, string pragma)
    {
        using var command = connection.CreateCommand();
        command.CommandText = $"PRAGMA {pragma};";
        return Convert.ToString(command.ExecuteScalar(), CultureInfo.InvariantCulture) ?? string.Empty;
    }

    private static void TryDelete(string path)
    {
        foreach (var file in new[] { path, path + "-wal", path + "-shm" })
        {
            try
            {
                if (File.Exists(file))
                {
                    File.Delete(file);
                }
            }
            catch (IOException)
            {
            }
        }
    }

    /// <summary>
    /// Adding a provider file must be the only step needed to ship a source. This drives the real
    /// registration path and resolves every discovered id back out of the container, so a provider
    /// that reflection finds but the container cannot hand out fails the build's own check.
    /// </summary>
    private static void CheckMetadataProvidersAreDiscovered(List<string> failures)
    {
        var discovered = MetadataSourceRegistry.All;

        AssertTrue(failures, discovered.Count > 1, "reflection discovers the whole provider set");

        var ids = discovered.Select(descriptor => descriptor.Id).ToList();
        AssertEqual(
            failures,
            ids.Count,
            ids.Distinct(StringComparer.OrdinalIgnoreCase).Count(),
            "discovered provider ids are unique");

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddAllMetadataProviders();

        using var provider = services.BuildServiceProvider();

        foreach (var descriptor in discovered)
        {
            var resolved = provider.GetKeyedService<IMetadataProvider>(descriptor.Id);

            AssertTrue(failures, resolved is not null, $"container resolves provider '{descriptor.Id}'");

            if (resolved is not null)
            {
                AssertEqual(
                    failures,
                    descriptor.Id,
                    resolved.Id,
                    $"provider resolved for key '{descriptor.Id}' reports its own id");
            }

            AssertTrue(
                failures,
                !string.IsNullOrWhiteSpace(descriptor.Name),
                $"provider '{descriptor.Id}' declares a display name");
        }

        // A bare media type must resolve to that type's default source, which is what the aggregator
        // asks for when the caller names no source at all.
        foreach (var mediaType in discovered.SelectMany(descriptor => descriptor.MediaTypes).Distinct())
        {
            var fallback = provider.GetKeyedService<IMetadataProvider>(mediaType);

            AssertTrue(failures, fallback is not null, $"bare type '{mediaType}' has a default source");

            if (fallback is not null)
            {
                AssertTrue(
                    failures,
                    fallback.MediaTypes.Contains(mediaType, StringComparer.OrdinalIgnoreCase),
                    $"default source for '{mediaType}' serves '{mediaType}'");
            }
        }
    }

    /// <summary>
    /// The list screen renders hundreds of cards, so the heavy text columns must not ride along.
    /// This is the contract that keeps the library payload small; only the detail shape carries them.
    /// </summary>
    private static void CheckListPayloadStaysLight(List<string> failures)
    {
        var heavy = new[] { "Notes", "TranslatedSynopsis", "ExternalRatingsJson", "UnlockedAchievements" };
        var listFields = typeof(MediaListDto).GetProperties().Select(property => property.Name).ToList();

        foreach (var member in heavy)
        {
            AssertFalse(
                failures,
                listFields.Contains(member),
                $"MediaListDto does not carry the heavy '{member}' column");
        }

        var detailFields = typeof(MediaDetailDto).GetProperties().Select(property => property.Name).ToList();

        foreach (var member in heavy)
        {
            AssertTrue(
                failures,
                detailFields.Contains(member),
                $"MediaDetailDto still carries '{member}'");
        }

        // The detail shape must be a superset, or the client's shared field mapping breaks.
        var missing = listFields.Except(detailFields, StringComparer.Ordinal).ToList();
        AssertEqual(failures, 0, missing.Count, $"detail is a superset of list (missing: {string.Join(',', missing)})");
    }

    /// <summary>
    /// A library card and the detail screen it opens must report the same episode and chapter totals.
    ///
    /// They used to disagree on every show: the list mapped the DTO inside the query, which EF could
    /// not translate, so it evaluated in memory with an unloaded (empty) season collection and every
    /// aggregate read 0 — "0 / 0" next to a correct "0 / 11" one click later. Both endpoints now go
    /// through MediaResponseMapper over a loaded graph, so the totals are one value by construction.
    /// </summary>
    private static void CheckListAndDetailTotalsAgree(List<string> failures)
    {
        var show = new TvShow { Title = "The Promised Neverland Season 2" };
        show.Seasons.Add(TvSeason.CreateFirst(11, null, MediaStatus.Planned, show.Id));

        var manga = new Manga { Title = "Noragami" };
        manga.AddVolume(
            MangaVolume.CreateFrom(
                1,
                "Volume 1",
                null,
                100,
                0,
                3,
                0,
                MediaStatus.Planned,
                null,
                null,
                null,
                manga.Id));
        manga.AddVolume(
            MangaVolume.CreateFrom(
                2,
                "Volume 2",
                null,
                100,
                0,
                5,
                0,
                MediaStatus.Planned,
                null,
                null,
                null,
                manga.Id));
        manga.RecordTotalChapters(8);

        foreach (var (item, label) in new (MediaItem, string)[] { (show, "show"), (manga, "manga") })
        {
            var listDto = MediaResponseMapper.ToListDto(item);
            var detailDto = MediaResponseMapper.ToDetailDto(item);

            AssertEqual(
                failures,
                listDto.TotalEpisodesCount,
                detailDto.TotalEpisodesCount,
                $"{label}: list and detail report the same episode total"
            );
            AssertEqual(
                failures,
                listDto.TotalEpisodesWatched,
                detailDto.TotalEpisodesWatched,
                $"{label}: list and detail report the same watched count"
            );
            AssertEqual(
                failures,
                listDto.TotalChapters,
                detailDto.TotalChapters,
                $"{label}: list and detail read one canonical chapter total"
            );
        }

        AssertEqual(
            failures,
            11,
            MediaResponseMapper.ToListDto(show).TotalEpisodesCount,
            "an 11-episode season sums to 11, not 0"
        );
        AssertEqual(
            failures,
            8,
            MediaResponseMapper.ToListDto(manga).TotalChapters,
            "the series counter wins over the volume sum"
        );

        // A show with no season rows has no episode count to report; 0 must not read as "watched 0 of 0".
        AssertEqual(
            failures,
            0,
            MediaResponseMapper.ToListDto(new TvShow { Title = "Empty" }).TotalEpisodesCount,
            "a seasonless show reports no episodes"
        );
    }

    /// <summary>The status is serialised as an integer and the client's maps are keyed on 0..4.</summary>
    private static void CheckStatusWireContract(List<string> failures)
    {
        AssertEqual(failures, 0, (int)MediaStatus.Planned, "Planned is 0");
        AssertEqual(failures, 1, (int)MediaStatus.InProgress, "InProgress is 1");
        AssertEqual(failures, 2, (int)MediaStatus.Completed, "Completed is 2");
        AssertEqual(failures, 3, (int)MediaStatus.OnHold, "OnHold is 3");
        AssertEqual(failures, 4, (int)MediaStatus.Dropped, "Dropped is 4");
        AssertEqual(failures, 5, Enum.GetValues<MediaStatus>().Length, "the status enum has exactly five members");
    }

    private static void CheckProviderConnectionTestIsNotShadowed(List<string> failures)
    {
        // Every provider declares its own TestConnectionAsync, but the settings screen only ever sees
        // the interface. A default interface member (or one that a derived class does not properly
        // override) silently shadows them all, and the probe that reports "OK" is the one searching
        // for the literal word "test" — which succeeds for an API key the provider actually rejects.
        foreach (var type in typeof(IMetadataProvider).Assembly
                     .GetTypes()
                     .Where(t => !t.IsAbstract && typeof(IMetadataProvider).IsAssignableFrom(t)))
        {
            var resolved = type.GetMethod("TestConnectionAsync");
            AssertTrue(
                failures,
                resolved is not null,
                $"{type.Name} exposes TestConnectionAsync");

            // Inheriting the base probe is fine. Declaring its own is only reachable through the
            // interface when the base declared the member virtual, which is what the previous
            // default-interface-method arrangement silently failed to do.
            if (resolved?.DeclaringType == type)
            {
                AssertTrue(
                    failures,
                    type.BaseType?.GetMethod("TestConnectionAsync") is { IsVirtual: true },
                    $"{type.Name}'s TestConnectionAsync override is reachable through IMetadataProvider");
            }
        }
    }

    /// <summary>MangaDex's vocabulary has to land on the same relation types the tab groups on.</summary>
    private static void CheckMangaDexRelationTypes(List<string> failures)
    {
        AssertEqual(failures, "SEQUEL", MangaDexMetadataProvider.MapRelationType("sequel"), "sequel is SEQUEL");
        AssertEqual(failures, "PREQUEL", MangaDexMetadataProvider.MapRelationType("prequel"), "prequel is PREQUEL");
        AssertEqual(
            failures,
            "PREQUEL",
            MangaDexMetadataProvider.MapRelationType("preserialization"),
            "preserialization is PREQUEL"
        );
        AssertEqual(failures, "SPIN_OFF", MangaDexMetadataProvider.MapRelationType("spin_off"), "spin_off is SPIN_OFF");
        AssertEqual(
            failures,
            "SIDE_STORY",
            MangaDexMetadataProvider.MapRelationType("side_story"),
            "side_story is SIDE_STORY"
        );
        AssertEqual(
            failures,
            "ALTERNATIVE",
            MangaDexMetadataProvider.MapRelationType("alternate_version"),
            "alternate_version is ALTERNATIVE"
        );
        AssertEqual(
            failures,
            "ADAPTATION",
            MangaDexMetadataProvider.MapRelationType("adapted_from"),
            "adapted_from is ADAPTATION"
        );
        AssertEqual(
            failures,
            "ADAPTATION",
            MangaDexMetadataProvider.MapRelationType("adaptation"),
            "adaptation is ADAPTATION"
        );
        // Unmapped MangaDex words still have to be a row rather than a dropped relation.
        AssertEqual(failures, "OTHER", MangaDexMetadataProvider.MapRelationType("doujinshi"), "doujinshi is OTHER");
        AssertEqual(failures, "OTHER", MangaDexMetadataProvider.MapRelationType(null), "a missing kind is OTHER");
    }

    private static void CheckImdbSuggestionPartition(List<string> failures)
    {
        AssertEqual(failures, "d", ImdbMetadataProvider.PartitionOf("Dune"), "IMDb keeps a latin first letter");
        AssertEqual(failures, "d", ImdbMetadataProvider.PartitionOf("dune"), "IMDb lowercases the partition");
        AssertEqual(failures, "2", ImdbMetadataProvider.PartitionOf("2 Guns"), "IMDb keeps a digit partition");
        AssertEqual(
            failures,
            "a",
            ImdbMetadataProvider.PartitionOf("Дюна"),
            "a Cyrillic title falls back to the 'a' partition instead of a 404"
        );
        AssertEqual(
            failures,
            "a",
            ImdbMetadataProvider.PartitionOf("Дюна: Месяц"),
            "a Cyrillic title with punctuation still falls back to the 'a' partition"
        );
        AssertEqual(
            failures,
            "a",
            ImdbMetadataProvider.PartitionOf("À La Carte"),
            "an accented latin letter is not a CDN partition either"
        );
    }

    /// <summary>
    /// Spirited Away (a movie) once landed in the TV series tab: the q string of a "TV movie"
    /// contains "tv", so anything television-flavoured was filed as a series. Only a real
    /// series/mini-series qid is a tvshow now, everything filmed is a movie, and games are dropped.
    /// </summary>
    private static void CheckImdbTypeClassification(List<string> failures)
    {
        AssertEqual(failures, "tvshow", ImdbMetadataProvider.Classify("tvSeries", "TV series"), "a TV series is a tvshow");
        AssertEqual(failures, "tvshow", ImdbMetadataProvider.Classify("tvMiniSeries", "TV mini-series"), "a TV mini-series is a tvshow");
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("movie", "feature"), "a feature is a movie");
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("tvMovie", "TV movie"), "a TV movie is NOT a tvshow");
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("tvSpecial", "TV special"), "a TV special is NOT a tvshow");
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("short", "short"), "a short is a movie");
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("video", "video"), "a video is a movie");
        AssertEqual(failures, "", ImdbMetadataProvider.Classify("videoGame", "video game"), "a video game is dropped");
        // The q label alone must never flip a TV movie into a series without a series qid.
        AssertEqual(failures, "movie", ImdbMetadataProvider.Classify("featureFfilm", "TV movie"), "a q label with 'tv' without a series qid stays a movie");
    }

    /// <summary>
    /// Changing the source order or toggling a source must invalidate every cached answer that was
    /// built under the old settings: the version that rides in the aggregator's cache keys is what
    /// makes the next search re-read the new priorities without a server restart.
    /// </summary>
    private static void CheckSourcePriorityVersionBump(List<string> failures)
    {
        var services = new ServiceCollection();
        services.AddMemoryCache();
        using var provider = services.BuildServiceProvider();

        var service = new SourcePriorityService(
            provider.GetRequiredService<IServiceScopeFactory>(),
            provider.GetRequiredService<IMemoryCache>(),
            NullLogger<SourcePriorityService>.Instance);

        AssertTrue(failures, service.Version >= 1, "the priority version starts positive");
        var before = service.Version;
        service.InvalidateCache();
        AssertEqual(failures, before + 1, service.Version, "InvalidateCache bumps the priority version");
    }

    private static void CheckSimklSearchSegments(List<string> failures)
    {
        AssertEqual(
            failures,
            "movie",
            SimklMetadataProvider.SearchSegmentOf("movie"),
            "Simkl search path for movies is singular"
        );
        AssertEqual(failures, "tv", SimklMetadataProvider.SearchSegmentOf("tvshow"), "Simkl search path for TV");
        AssertEqual(failures, "anime", SimklMetadataProvider.SearchSegmentOf("anime"), "Simkl search path for anime");
        AssertEqual(
            failures,
            "anime",
            SimklMetadataProvider.SearchSegmentOf("unknown"),
            "an unrecognised media type falls back to anime"
        );

        // The detail path is plural where the search path is singular, which is the whole reason
        // movie details used to 404 and fall back to a rating-less search hit.
        AssertEqual(
            failures,
            "movies",
            SimklMetadataProvider.DetailSegmentOf("movie"),
            "Simkl detail path for movies is plural"
        );
        AssertEqual(
            failures,
            "tv",
            SimklMetadataProvider.DetailSegmentOf("tvshow"),
            "Simkl detail path for TV"
        );
        AssertEqual(
            failures,
            "anime",
            SimklMetadataProvider.DetailSegmentOf("anime"),
            "Simkl detail path for anime"
        );
    }

    private static void CheckBookPageCountSurvivesMerge(List<string> failures)
    {
        var withPages = new ExternalMediaDto
        {
            ExternalId = "/works/OL893414W",
            ExternalSource = "OpenLibrary",
            Title = "Dune",
            Type = "book",
            Author = "Frank Herbert",
            TotalCount = 608
        };

        var withoutPages = new ExternalMediaDto
        {
            ExternalId = "/works/OL17717458W",
            ExternalSource = "OpenLibrary",
            Title = "Дюна",
            Type = "book"
        };

        AssertEqual(
            failures,
            608,
            MediaMerger.Merge(withPages, withoutPages).TotalCount,
            "a source with no page count does not wipe the pages another source supplied"
        );
        AssertEqual(
            failures,
            608,
            MediaMerger.Merge(withoutPages, withPages).TotalCount,
            "pages survive regardless of which source answers first"
        );
        AssertEqual(
            failures,
            608,
            MediaMerger.Merge(withPages, withoutPages with { TotalCount = 0 }).TotalCount,
            "an explicit zero page count does not overwrite real pages"
        );

        var book = new Book { Title = "Dune", Author = string.Empty };
        MediaMetadataApplier.ApplyIfMissing(book, withPages);
        AssertEqual(failures, 608, book.TotalPages, "enrichment fills the page count the source reported");

        var noAuthor = new Book { Title = "Dune", Author = string.Empty };
        MediaMetadataApplier.ApplyIfMissing(noAuthor, withPages with { Author = "Frank Herbert" });
        AssertEqual(failures, "Frank Herbert", noAuthor.Author, "enrichment fills a missing author");

        var existing = new Book { Title = "Дюна", Author = "string", TotalPages = 412 };
        MediaMetadataApplier.ApplyIfMissing(existing, withoutPages);
        AssertEqual(
            failures,
            412,
            existing.TotalPages,
            "enrichment with no page count leaves the stored page count alone"
        );

        MediaMetadataApplier.ApplyIfMissing(existing, withPages);
        AssertEqual(
            failures,
            412,
            existing.TotalPages,
            "enrichment never overwrites a page count the user already has"
        );
    }

    private const string KitsuAnimeSearchJson = """
        {"data":[{"id":"1","type":"anime","attributes":{"canonicalTitle":"Cowboy Bebop","synopsis":"Space bounty hunters.","averageRating":"82.27","userCount":162398,"startDate":"1998-04-03","status":"finished","episodeCount":26,"episodeLength":24,"posterImage":{"large":"https://cdn.example/l.png","original":"https://cdn.example/o.png"}}}]}
        """;

    private const string KitsuMangaSearchJson = """
        {"data":[{"id":"56355","type":"manga","attributes":{"canonicalTitle":"Sousou no Frieren","averageRating":"84.2","userCount":7689,"startDate":"2020-04-28","status":"current"}}]}
        """;

    private const string KitsuMangaDetailsJson = """
        {"data":{"id":"56355","type":"manga","attributes":{"canonicalTitle":"Sousou no Frieren","averageRating":"84.2","userCount":7689,"startDate":"2020-04-28","status":"current"}}}
        """;

    private const string KitsuAnimeDetailsJson = """
        {"data":{"id":"1","type":"anime","attributes":{"canonicalTitle":"Cowboy Bebop","averageRating":"82.27","userCount":162398,"startDate":"1998-04-03","status":"finished"}}}
        """;

    /// <summary>
    /// Kitsu returns averageRating as a JSON string on a 100-point scale, and manga lives on a
    /// separate edge/manga collection. This pins both: the string parse with the /10 conversion and
    /// the request URL per media type, using a canned payload shaped like the real API.
    /// </summary>
    private static void CheckKitsuRatingMapping(List<string> failures)
    {
        AssertTrue(
            failures,
            KitsuMetadataProvider.Source.MediaTypes.Contains("anime") &&
            KitsuMetadataProvider.Source.MediaTypes.Contains("manga"),
            "kitsu declares both anime and manga");

        Uri? requested = null;
        var factory = new StubHttpClientFactory(request =>
        {
            requested = request.RequestUri;
            var path = request.RequestUri!.AbsolutePath;
            var json = path.Contains("/manga/", StringComparison.Ordinal) ? KitsuMangaDetailsJson
                : path.Contains("/manga", StringComparison.Ordinal) ? KitsuMangaSearchJson
                : path.Contains("/anime/", StringComparison.Ordinal) ? KitsuAnimeDetailsJson
                : KitsuAnimeSearchJson;
            return Task.FromResult(new HttpResponseMessage { Content = new StringContent(json) });
        });

        var animeResults = new KitsuMetadataProvider(factory)
            .SearchAsync("Cowboy Bebop", CancellationToken.None).GetAwaiter().GetResult();

        AssertTrue(
            failures,
            requested?.AbsoluteUri.StartsWith("https://kitsu.io/api/edge/anime?", StringComparison.Ordinal) == true,
            $"kitsu anime search goes to https://kitsu.io/api/edge/anime (was {requested})");

        if (animeResults is [var anime])
        {
            AssertEqual(failures, "anime", anime.Type, "kitsu anime result is typed anime");
            AssertEqual(failures, 8.2, anime.Rating ?? 0, "kitsu string rating converts from 100- to 10-point scale");
            AssertEqual(failures, 162398, anime.RatingVotes ?? 0, "kitsu votes come from userCount");
            AssertTrue(
                failures,
                anime.Ratings is [{ Source: "Kitsu", Rating: 8.2, Votes: 162398 }],
                "kitsu badge payload carries source, 10-point score and votes");
        }
        else
        {
            AssertTrue(failures, false, "kitsu anime search returns exactly one result");
        }

        var mangaProvider = new KitsuMetadataProvider(factory, "manga:kitsu");
        var mangaResults = mangaProvider
            .SearchAsync("frieren", CancellationToken.None).GetAwaiter().GetResult();

        AssertTrue(
            failures,
            requested?.AbsoluteUri.StartsWith("https://kitsu.io/api/edge/manga?", StringComparison.Ordinal) == true,
            $"kitsu manga search goes to https://kitsu.io/api/edge/manga (was {requested})");

        if (mangaResults is [var manga])
        {
            AssertEqual(failures, "manga", manga.Type, "kitsu manga result is typed manga");
            AssertEqual(failures, 8.4, manga.Rating ?? 0, "kitsu manga rating converts from 100- to 10-point scale");
            AssertEqual(failures, 7689, manga.RatingVotes ?? 0, "kitsu manga votes come from userCount");
        }
        else
        {
            AssertTrue(failures, false, "kitsu manga search returns exactly one result");
        }

        var mangaDetails = mangaProvider
            .GetDetailsAsync("56355", "Sousou no Frieren", CancellationToken.None).GetAwaiter().GetResult();

        AssertTrue(
            failures,
            requested?.AbsolutePath == "/api/edge/manga/56355" && requested.Scheme == "https" && requested.Host == "kitsu.io",
            $"kitsu manga details go to https://kitsu.io/api/edge/manga/{{id}} (was {requested})");
        AssertTrue(failures, mangaDetails is not null, "kitsu manga details map");
        AssertEqual(failures, "manga", mangaDetails?.Type, "kitsu manga details are typed manga");
        AssertEqual(failures, 8.4, mangaDetails?.Rating ?? 0, "kitsu manga details rating is on the 10-point scale");
        AssertEqual(failures, 7689, mangaDetails?.RatingVotes ?? 0, "kitsu manga details votes come from userCount");
    }

    private static void CheckSteamVerticalCovers(List<string> failures)
    {
        var steamFactory = new StubHttpClientFactory(request =>
        {
            var uri = request.RequestUri!.AbsoluteUri;
            if (uri.Contains("storesearch"))
            {
                var searchJson = """{"items":[{"id":367520,"name":"Hollow Knight","tiny_image":"https://cdn.example/capsule.jpg"}]}""";
                return Task.FromResult(new HttpResponseMessage { Content = new StringContent(searchJson) });
            }

            var detailsJson = """{"367520":{"success":true,"data":{"name":"Hollow Knight","header_image":"https://cdn.example/header.jpg"}}}""";
            return Task.FromResult(new HttpResponseMessage { Content = new StringContent(detailsJson) });
        }, SteamMetadataProvider.Source.BaseAddress);

        var steamProvider = new SteamMetadataProvider(steamFactory);
        var steamSearch = steamProvider.SearchAsync("Hollow Knight", CancellationToken.None).GetAwaiter().GetResult();
        AssertEqual(
            failures,
            "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg",
            steamSearch.FirstOrDefault()?.CoverUrl,
            "steam search produces vertical library poster");
        AssertEqual(failures, "367520", steamSearch.FirstOrDefault()?.SteamAppId, "steam search sets steam app id");

        var steamDetails = steamProvider.GetDetailsAsync("367520", "Hollow Knight", CancellationToken.None).GetAwaiter().GetResult();
        AssertEqual(
            failures,
            "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg",
            steamDetails?.CoverUrl,
            "steam details produces vertical library poster");
        AssertEqual(failures, "367520", steamDetails?.SteamAppId, "steam details sets steam app id");

        var rawgFactory = new StubHttpClientFactory(request =>
        {
            var uri = request.RequestUri!.AbsoluteUri;
            if (uri.Contains("games?search="))
            {
                var searchJson = """
                {"results":[
                    {"id":9767,"name":"Hollow Knight","background_image":"https://media.rawg.io/bg.jpg","stores":[{"url":"https://store.steampowered.com/app/367520/Hollow_Knight/"}]},
                    {"id":9999,"name":"Console Only","background_image":"https://media.rawg.io/console.jpg","stores":[{"url":"https://store.playstation.com/app/123"}]}
                ]}
                """;
                return Task.FromResult(new HttpResponseMessage { Content = new StringContent(searchJson) });
            }

            if (uri.EndsWith("/stores?key=test-key") || uri.Contains("/stores?"))
            {
                var storesJson = """{"results":[{"url":"https://store.steampowered.com/app/367520/"}]}""";
                return Task.FromResult(new HttpResponseMessage { Content = new StringContent(storesJson) });
            }

            var gameDetailsJson = """
            {"id":9767,"name":"Hollow Knight","background_image":"https://media.rawg.io/bg.jpg","stores":[{"id":1,"url":"","store":{"id":1,"slug":"steam"}}]}
            """;
            return Task.FromResult(new HttpResponseMessage { Content = new StringContent(gameDetailsJson) });
        }, RawgMetadataProvider.Source.BaseAddress);

        var rawgOptions = Microsoft.Extensions.Options.Options.Create(new ExternalApiOptions { RawgApiKey = "test-key" });
        var rawgProvider = new RawgMetadataProvider(rawgFactory, rawgOptions, Microsoft.Extensions.Logging.Abstractions.NullLogger<RawgMetadataProvider>.Instance);

        var rawgSearch = rawgProvider.SearchAsync("Hollow Knight", CancellationToken.None).GetAwaiter().GetResult();
        AssertEqual(
            failures,
            "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg",
            rawgSearch.FirstOrDefault(x => x.ExternalId == "9767")?.CoverUrl,
            "rawg search with steam store produces vertical library poster");
        AssertEqual(
            failures,
            "367520",
            rawgSearch.FirstOrDefault(x => x.ExternalId == "9767")?.SteamAppId,
            "rawg search sets steam app id");
        AssertEqual(
            failures,
            "https://media.rawg.io/console.jpg",
            rawgSearch.FirstOrDefault(x => x.ExternalId == "9999")?.CoverUrl,
            "rawg without steam store falls back to background_image");

        var rawgDetails = rawgProvider.GetDetailsAsync("9767", "Hollow Knight", CancellationToken.None).GetAwaiter().GetResult();
        AssertEqual(
            failures,
            "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/367520/library_600x900.jpg",
            rawgDetails?.CoverUrl,
            "rawg details fetches stores endpoint and produces vertical library poster");
        AssertEqual(failures, "367520", rawgDetails?.SteamAppId, "rawg details sets steam app id");

        var merged = MediaMerger.Merge(
            new ExternalMediaDto { ExternalId = "1", Title = "Test", Type = "game", SteamAppId = "367520" },
            new ExternalMediaDto { ExternalId = "2", Title = "Test", Type = "game" });
        AssertEqual(failures, "367520", merged.SteamAppId, "media merger preserves steam app id");
    }

    private sealed class StubHttpClientFactory(Func<HttpRequestMessage, Task<HttpResponseMessage>> responder, string? baseAddress = null) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) =>
            new(new StubHttpMessageHandler(responder)) { BaseAddress = new Uri(baseAddress ?? KitsuMetadataProvider.Source.BaseAddress) };
    }

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            responder(request);
    }

    private static void AssertTrue(List<string> failures, bool condition, string label)
    {
        if (!condition)
        {
            failures.Add($"{label}: expected true");
        }
    }

    private static void AssertFalse(List<string> failures, bool condition, string label)
    {
        if (condition)
        {
            failures.Add($"{label}: expected false");
        }
    }

    private static void AssertEqual<T>(List<string> failures, T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            failures.Add($"{label}: expected <{expected}> but was <{actual}>");
        }
    }

    private static void CheckAdvancedStatsCalculation(List<string> failures)
    {
        var now = new DateTime(2026, 10, 7, 12, 0, 0, DateTimeKind.Utc);

        var emptyStats = AdvancedStatsCalculator.Calculate([], now);
        AssertEqual(failures, 0, emptyStats.TotalTitles, "empty TotalTitles");
        AssertEqual(failures, 0, emptyStats.CompletedTitles, "empty CompletedTitles");
        AssertEqual(failures, 0.0, emptyStats.CompletionRatePercent, "empty CompletionRatePercent");
        AssertEqual(failures, 0.0, emptyStats.TotalHours, "empty TotalHours");
        AssertEqual(failures, 0.0, emptyStats.TotalDays, "empty TotalDays");
        AssertEqual(failures, 10, emptyStats.ScoreDistribution.Count, "empty ScoreDistribution count");
        AssertEqual(failures, 0, emptyStats.ScoreDistribution[1], "empty ScoreDistribution 1");
        AssertEqual(failures, 0, emptyStats.ScoreDistribution[10], "empty ScoreDistribution 10");
        AssertEqual(failures, 12, emptyStats.MonthlyCompletions.Count, "empty MonthlyCompletions count");
        AssertEqual(failures, 0, emptyStats.CurrentStreakDays, "empty CurrentStreakDays");

        var game = new VideoGame
        {
            Title = "Game 1",
            Platform = "PC",
            HoursPlayed = 20,
            Score = 8,
            Status = MediaStatus.Completed,
            FinishedAt = now.AddDays(-1),
            UpdatedAt = now.AddDays(-1),
            Genres = "Action, RPG",
        };

        var plannedGame = new VideoGame
        {
            Title = "Planned Game",
            Platform = "PC",
            HoursPlayed = 12,
            Status = MediaStatus.Planned,
        };

        var movie1 = new Movie
        {
            Title = "Movie 1",
            DurationMinutes = 120,
            Score = 9,
            Status = MediaStatus.Completed,
            FinishedAt = now,
            UpdatedAt = now,
            Genres = "Drama, Sci-Fi",
        };

        var movie2 = new Movie
        {
            Title = "Movie 2",
            DurationMinutes = 120,
            Score = null,
            Status = MediaStatus.Planned,
            UpdatedAt = now.AddDays(-2),
            Genres = "Drama",
        };

        var series = new TvShow
        {
            Title = "Show 1",
            IsAnime = false,
            EpisodeDurationMinutes = 60,
            Score = 7,
            Status = MediaStatus.InProgress,
            UpdatedAt = now,
            Genres = "Drama, Crime",
            Seasons =
            [
                new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 10, TotalEpisodes = 10 }
            ],
        };

        var anime = new TvShow
        {
            Title = "Anime 1",
            IsAnime = true,
            EpisodeDurationMinutes = null,
            Score = 9,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-1),
            Genres = "Anime, Action",
            Seasons =
            [
                new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 5, TotalEpisodes = 12 }
            ],
        };

        var plannedShow = new TvShow
        {
            Title = "Planned Show",
            IsAnime = false,
            EpisodeDurationMinutes = 60,
            Status = MediaStatus.Planned,
            Seasons =
            [
                new TvSeason { SeasonNumber = 1, Title = "S1", CurrentEpisode = 4, TotalEpisodes = 12 }
            ],
        };

        var book = new Book
        {
            Title = "Book 1",
            Author = "Author 1",
            CurrentPage = 200,
            TotalPages = 400,
            Score = null,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-3),
            Genres = "Fantasy",
        };

        var plannedBook = new Book
        {
            Title = "Planned Book",
            Author = "Author",
            CurrentPage = 100,
            TotalPages = 400,
            Status = MediaStatus.Planned,
        };

        var manga = new Manga
        {
            Title = "Manga 1",
            CurrentChapter = 50,
            TotalChapters = 100,
            Score = null,
            Status = MediaStatus.InProgress,
            UpdatedAt = now.AddDays(-4),
            Genres = "Action",
        };

        var plannedManga = new Manga
        {
            Title = "Planned Manga",
            CurrentChapter = 25,
            TotalChapters = 100,
            Status = MediaStatus.Planned,
        };

        var items = new MediaItem[] { game, plannedGame, movie1, movie2, series, anime, plannedShow, book, plannedBook, manga, plannedManga };
        var stats = AdvancedStatsCalculator.Calculate(items, now);

        AssertEqual(failures, 11, stats.TotalTitles, "stats TotalTitles");
        AssertEqual(failures, 2, stats.CompletedTitles, "stats CompletedTitles");
        AssertEqual(failures, Math.Round(2.0 / 11.0 * 100.0, 1), stats.CompletionRatePercent, "stats CompletionRatePercent");

        AssertEqual(failures, 20.0, stats.GameHours, "stats GameHours");
        AssertEqual(failures, 2.0, stats.MovieHours, "stats MovieHours");
        AssertEqual(failures, 10.0, stats.SeriesHours, "stats SeriesHours");
        AssertEqual(failures, 2.0, stats.AnimeHours, "stats AnimeHours");
        AssertEqual(failures, 5.0, stats.BookHours, "stats BookHours");
        AssertEqual(failures, 5.0, stats.MangaHours, "stats MangaHours");

        AssertEqual(failures, 44.0, stats.TotalHours, "stats TotalHours");
        AssertEqual(failures, Math.Round(44.0 / 24.0, 1), stats.TotalDays, "stats TotalDays");

        AssertEqual(failures, 200, stats.TotalPagesRead, "stats TotalPagesRead");
        AssertEqual(failures, 50, stats.TotalChaptersRead, "stats TotalChaptersRead");
        AssertEqual(failures, 15, stats.TotalEpisodesWatched, "stats TotalEpisodesWatched");
        AssertEqual(failures, 10, stats.SeriesEpisodesWatched, "stats SeriesEpisodesWatched");
        AssertEqual(failures, 5, stats.AnimeEpisodesWatched, "stats AnimeEpisodesWatched");

        var animeMovie = new Movie
        {
            Title = "Spirited Away",
            IsAnime = true,
            DurationMinutes = 125,
            Status = MediaStatus.Completed,
        };
        var animeMovieStats = AdvancedStatsCalculator.Calculate([animeMovie], now);
        AssertEqual(failures, 0.0, animeMovieStats.MovieHours, "anime movie MovieHours should be 0");
        AssertEqual(failures, Math.Round(125.0 / 60.0, 1), animeMovieStats.AnimeHours, "anime movie AnimeHours");

        AssertEqual(failures, 8.3, stats.AverageScore, "stats AverageScore");
        AssertEqual(failures, 1, stats.ScoreDistribution[7], "stats ScoreDistribution 7");
        AssertEqual(failures, 1, stats.ScoreDistribution[8], "stats ScoreDistribution 8");
        AssertEqual(failures, 2, stats.ScoreDistribution[9], "stats ScoreDistribution 9");
        AssertEqual(failures, 0, stats.ScoreDistribution[10], "stats ScoreDistribution 10");

        AssertEqual(failures, 8.0, stats.AverageScoreByType["game"], "stats AverageScoreByType game");
        AssertEqual(failures, 9.0, stats.AverageScoreByType["movie"], "stats AverageScoreByType movie");
        AssertEqual(failures, 7.0, stats.AverageScoreByType["series"], "stats AverageScoreByType series");
        AssertEqual(failures, 9.0, stats.AverageScoreByType["anime"], "stats AverageScoreByType anime");

        AssertEqual(failures, 12, stats.MonthlyCompletions.Count, "stats MonthlyCompletions count");
        AssertEqual(failures, "2026-10", stats.MonthlyCompletions[^1].MonthYear, "stats MonthlyCompletions current month");
        AssertEqual(failures, 2, stats.MonthlyCompletions[^1].Count, "stats MonthlyCompletions count 2026-10");

        AssertTrue(failures, stats.CurrentStreakDays >= 2, "stats CurrentStreakDays");
        AssertTrue(failures, stats.TopGenres.Count > 0, "stats TopGenres not empty");
        AssertEqual(failures, "Action", stats.TopGenres[0].Genre, "stats TopGenres first is Action");
        AssertEqual(failures, 3, stats.TopGenres[0].Count, "stats TopGenres Action count");
    }

    private static void CheckAllMetadataProvidersSupportGenres(List<string> failures)
    {
        var providerTypes = typeof(IMetadataProvider).Assembly.GetTypes()
            .Where(t => typeof(IMetadataProvider).IsAssignableFrom(t) && !t.IsAbstract && !t.IsInterface)
            .ToList();

        foreach (var type in providerTypes)
        {
            var extracts = TestProviderGenreExtraction(type);
            if (!extracts)
            {
                failures.Add($"FAILED: Provider {type.Name} does not extract genres");
            }
        }
    }

    private static bool TestProviderGenreExtraction(Type type)
    {
        try
        {
            var apiOptions = Microsoft.Extensions.Options.Options.Create(new ExternalApiOptions
            {
                KinopoiskApiKey = "test-key",
                TmdbApiKey = "test-key",
                RawgApiKey = "test-key",
                IgdbApiKey = "test:secret",
                SimklApiKey = "test-key",
                TvdbApiKey = "test-key",
                GoogleBooksApiKey = "test-key"
            });

            if (type == typeof(KinopoiskMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"kinopoiskId":301,"nameRu":"Матрица","genres":[{"genre":"фантастика"},{"genre":"боевик"}]}""")
                }));
                var provider = new KinopoiskMetadataProvider(factory, apiOptions, "movie");
                var dto = provider.GetDetailsAsync("301", "Матрица", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("фантастика");
            }

            if (type == typeof(TmdbMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"id":550,"title":"Fight Club","genres":[{"id":18,"name":"Drama"}]}""")
                }));
                var provider = new TmdbMetadataProvider(factory, apiOptions, Microsoft.Extensions.Logging.Abstractions.NullLogger<TmdbMetadataProvider>.Instance, "movie");
                var dto = provider.GetDetailsAsync("550", "Fight Club", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Drama");
            }

            if (type == typeof(AniListMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"data":{"Media":{"id":1,"title":{"english":"Cowboy Bebop"},"genres":["Action","Sci-Fi"]}}}""")
                }));
                var provider = new AniListMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("1", "Cowboy Bebop", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(RawgMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"id":3498,"name":"GTA V","genres":[{"id":4,"name":"Action"}]}""")
                }));
                var provider = new RawgMetadataProvider(factory, apiOptions, Microsoft.Extensions.Logging.Abstractions.NullLogger<RawgMetadataProvider>.Instance);
                var dto = provider.GetDetailsAsync("3498", "GTA", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(SteamMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"367520":{"success":true,"data":{"name":"Hollow Knight","genres":[{"id":"1","description":"Action"},{"id":"2","description":"Indie"}]}}}""")
                }));
                var provider = new SteamMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("367520", "Hollow Knight", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(OpenLibraryMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"docs":[{"key":"/works/OL1","title":"Dune","subject":["Science Fiction","Adventure"]}]}""")
                }));
                var provider = new OpenLibraryMetadataProvider(factory);
                var dtos = provider.SearchAsync("Dune", CancellationToken.None).GetAwaiter().GetResult();
                return dtos.FirstOrDefault()?.Genres is { Count: > 0 } && dtos[0].Genres!.Contains("Science Fiction");
            }

            if (type == typeof(MangaDexMetadataProvider))
            {
                var factory = new StubHttpClientFactory(req =>
                {
                    var uri = req.RequestUri!.AbsoluteUri;
                    if (uri.Contains("/statistics/"))
                    {
                        return Task.FromResult(new HttpResponseMessage { Content = new StringContent("""{"statistics":{}}""") });
                    }
                    var json = """
                    {"data":{"id":"f98660a0-8127-46e8-8199-53e7f4a21183","type":"manga","attributes":{"title":{"en":"Sousou no Frieren"},"tags":[{"attributes":{"name":{"en":"Adventure"}}},{"attributes":{"name":{"en":"Fantasy"}}}]}}}
                    """;
                    return Task.FromResult(new HttpResponseMessage { Content = new StringContent(json) });
                });
                var provider = new MangaDexMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("f98660a0-8127-46e8-8199-53e7f4a21183", "Frieren", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Adventure");
            }

            if (type == typeof(MangaUpdatesMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"series_id":1234,"title":"Berserk","genres":[{"genre":"Action"},{"genre":"Dark Fantasy"}]}""")
                }));
                var provider = new MangaUpdatesMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("1234", "Berserk", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(JikanMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"data":{"mal_id":1,"title":"Cowboy Bebop","genres":[{"name":"Action"},{"name":"Sci-Fi"}]}}""")
                }));
                var provider = new JikanMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("1", "Cowboy Bebop", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(KitsuMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"data":{"id":"1","type":"anime","attributes":{"canonicalTitle":"Cowboy Bebop","categories":["Action","Sci-Fi"]}}}""")
                }));
                var provider = new KitsuMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("1", "Cowboy Bebop", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Action");
            }

            if (type == typeof(GoogleBooksMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"id":"xyz","volumeInfo":{"title":"Dune","categories":["Fiction","Sci-Fi"]}}""")
                }));
                var provider = new GoogleBooksMetadataProvider(factory, apiOptions);
                var dto = provider.GetDetailsAsync("xyz", "Dune", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Fiction");
            }

            if (type == typeof(IgdbMetadataProvider))
            {
                var factory = new StubHttpClientFactory(req =>
                {
                    if (req.RequestUri!.AbsoluteUri.Contains("token"))
                    {
                        return Task.FromResult(new HttpResponseMessage { Content = new StringContent("""{"access_token":"tok","expires_in":3600,"token_type":"bearer"}""") });
                    }
                    return Task.FromResult(new HttpResponseMessage { Content = new StringContent("""[{"id":10,"name":"Half-Life","genres":[{"id":1,"name":"Shooter"}]}]""") });
                });
                var provider = new IgdbMetadataProvider(factory, apiOptions);
                var dtos = provider.SearchAsync("Half-Life", CancellationToken.None).GetAwaiter().GetResult();
                return dtos.FirstOrDefault()?.Genres is { Count: > 0 } && dtos[0].Genres!.Contains("Shooter");
            }

            if (type == typeof(ImdbMetadataProvider))
            {
                var factory = new StubHttpClientFactory(req =>
                {
                    if (req.RequestUri!.AbsoluteUri.Contains("cinemeta"))
                    {
                        return Task.FromResult(new HttpResponseMessage
                        {
                            Content = new StringContent("""{"meta":{"id":"tt0111161","name":"Shawshank","genres":["Drama","Crime"]}}""")
                        });
                    }
                    return Task.FromResult(new HttpResponseMessage
                    {
                        Content = new StringContent("""{"d":[{"id":"tt0111161","l":"Shawshank","y":1994,"q":"feature"}]}""")
                    });
                });
                var provider = new ImdbMetadataProvider(factory, serviceKey: null, Microsoft.Extensions.Logging.Abstractions.NullLogger<ImdbMetadataProvider>.Instance);
                var dto = provider.GetDetailsAsync("tt0111161", "Shawshank", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Drama");
            }

            if (type == typeof(ShikimoriMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"id":1,"name":"Cowboy Bebop","genres":[{"name":"Action","russian":"Экшен"}]}""")
                }));
                var provider = new ShikimoriMetadataProvider(factory);
                var dto = provider.GetDetailsAsync("1", "Cowboy Bebop", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("Экшен");
            }

            if (type == typeof(SimklMetadataProvider))
            {
                var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage
                {
                    Content = new StringContent("""{"title":"Breaking Bad","genres":["drama","crime"]}""")
                }));
                var provider = new SimklMetadataProvider(factory, apiOptions);
                var dto = provider.GetDetailsAsync("38714", "Breaking Bad", CancellationToken.None).GetAwaiter().GetResult();
                return dto?.Genres is { Count: > 0 } && dto.Genres.Contains("drama");
            }

            if (type == typeof(TvdbMetadataProvider))
            {
                var factory = new StubHttpClientFactory(req =>
                {
                    if (req.RequestUri!.AbsoluteUri.Contains("login"))
                    {
                        return Task.FromResult(new HttpResponseMessage { Content = new StringContent("""{"data":{"token":"tok"}}""") });
                    }
                    return Task.FromResult(new HttpResponseMessage { Content = new StringContent("""{"data":[{"tvdb_id":"123","name":"Breaking Bad","genres":["Drama"]}]}""") });
                });
                var provider = new TvdbMetadataProvider(factory, apiOptions);
                var dtos = provider.SearchAsync("Breaking Bad", CancellationToken.None).GetAwaiter().GetResult();
                return dtos.FirstOrDefault()?.Genres is { Count: > 0 } && dtos[0].Genres!.Contains("Drama");
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    private static void CheckSmartListEvaluator(List<string> failures)
    {
        var anime = new TvShow { Title = "Attack on Titan", IsAnime = true };
        anime.Seasons.Add(TvSeason.CreateFirst(25, null, MediaStatus.Planned, anime.Id));
        var shortAnime = new TvShow { Title = "Ping Pong The Animation", IsAnime = true };
        shortAnime.Seasons.Add(TvSeason.CreateFirst(11, null, MediaStatus.Planned, shortAnime.Id));
        var movie = new Movie { Title = "Inception", DurationMinutes = 148, Score = 9 };
        var shortMovie = new Movie { Title = "Lunch Box", DurationMinutes = 80, Studio = "Studio Ghibli" };
        var book = new Book { Title = "The Hobbit", Author = "Tolkien", TotalPages = 310 };
        var items = new List<MediaItem> { anime, shortAnime, movie, shortMovie, book };

        // Test: category filter anime
        var animeOnly = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Categories = ["anime"] });
        AssertEqual(failures, 2, animeOnly.Count, "SmartList: anime category returns 2 shows");

        // Test: category movie
        var moviesOnly = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Categories = ["movie"] });
        AssertEqual(failures, 2, moviesOnly.Count, "SmartList: movie category returns 2 movies");

        // Test: MinScore filters
        var highScore = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { MinScore = 9 });
        AssertEqual(failures, 1, highScore.Count, "SmartList: MinScore=9 returns 1 item");
        AssertEqual(failures, "Inception", highScore[0].Title, "SmartList: MinScore=9 returns Inception");

        // Test: MaxDurationMinutes for movies
        var shortMovies = SmartListEvaluator.Evaluate(items,
            new SmartListQueryDto { Categories = ["movie"], MaxDurationMinutes = 100 });
        AssertEqual(failures, 1, shortMovies.Count, "SmartList: MaxDurationMinutes=100 returns 1 movie");
        AssertEqual(failures, "Lunch Box", shortMovies[0].Title, "SmartList: MaxDurationMinutes=100 returns short movie");

        // Test: MaxEpisodes for TvShow
        var shortShows = SmartListEvaluator.Evaluate(items,
            new SmartListQueryDto { Categories = ["anime"], MaxEpisodes = 13 });
        AssertEqual(failures, 1, shortShows.Count, "SmartList: MaxEpisodes=13 returns 1 anime");
        AssertEqual(failures, "Ping Pong The Animation", shortShows[0].Title, "SmartList: MaxEpisodes=13 returns short anime");

        // Test: CreatorContains
        var ghibli = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { CreatorContains = "ghibli" });
        AssertEqual(failures, 1, ghibli.Count, "SmartList: CreatorContains=ghibli returns 1 item");

        // Test: Limit
        var limited = SmartListEvaluator.Evaluate(items, new SmartListQueryDto { Limit = 2 });
        AssertEqual(failures, 2, limited.Count, "SmartList: Limit=2 returns 2 items");
    }

    private sealed class NoOpImageStorage : IImageStorageService
    {
        public Task<string?> SaveCoverAsync(
            string externalUrl,
            Guid itemId,
            CancellationToken ct = default,
            string folder = "cover"
        ) => Task.FromResult<string?>(externalUrl);

        public void DeleteCover(string? localCoverUrl) { }

        public void DeleteMediaFolder(Guid mediaId) { }
    }
}
