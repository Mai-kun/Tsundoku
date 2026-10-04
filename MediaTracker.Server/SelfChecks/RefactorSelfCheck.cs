using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Common.Cli;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence.Interceptors;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using MediaDetailDto = MediaTracker.Server.Features.Media.MediaContract.MediaDetailDto;
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
        CheckSourceRegistryIsSelfContained(failures);
        CheckExternalUrlDetection(failures);
        CheckRatingsSerialization(failures);
        CheckMangaGapEnrichment(failures);
        CheckMangaFormatFromSources(failures);
        CheckMangaFormatMergePrefersOel(failures);
        CheckMangaGapEnrichmentDoesNotOverwrite(failures);
        CheckMergeKeepsRuntimeAndGenres(failures);
        CheckMergeKeepsFinalChapterTotal(failures);
        CheckRealVolumesReplaceSeededSplit(failures);
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
        CheckVolumeProgressStepper(failures);
        CheckPlaceholderVolumes(failures);
        CheckReleaseStatusComputation(failures);
        CheckApiKeyLookup(failures);
        CheckCoverSizeLimit(failures);
        CheckCommandLineParsing(failures);
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
        CheckSimklSearchSegments(failures);
        CheckBookPageCountSurvivesMerge(failures);
        CheckProviderConnectionTestIsNotShadowed(failures);
        CheckListPayloadStaysLight(failures);
        CheckListAndDetailTotalsAgree(failures);
        CheckStatusWireContract(failures);

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
            "anilist,shikimori,mangadex,mangaupdates,jikan",
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
    /// A seeded series splits its chapter budget evenly across its stub volumes, so every volume
    /// starts with the same invented number. The real per-volume split a provider reports has to
    /// replace it, or "том 1 — 3 главы, том 2 — 5 глав" never appears.
    /// </summary>
    private static void CheckRealVolumesReplaceSeededSplit(List<string> failures)
    {
        var manga = new Manga { Title = "Noragami", TotalChapters = 8 };
        // Same order the create handler uses: the total lands on the row, then the stubs are seeded.
        manga.SeedPlaceholderVolumes(requestedVolumes: 2, totalChapters: 8, totalPages: null);

        AssertEqual(failures, 4, manga.Volumes[0].TotalChapters, "seed splits the budget evenly");
        AssertEqual(failures, 4, manga.Volumes[1].TotalChapters, "seed splits the budget evenly");

        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Noragami",
            Type = "manga",
            TotalCount = 8,
            Chapters = 8,
            VolumeDetails =
            [
                new ExternalMangaVolumeDto { Number = 1, Chapters = ["1", "2", "3"] },
                new ExternalMangaVolumeDto { Number = 2, Chapters = ["4", "5", "6", "7", "8"] },
            ],
        };

        MediaMetadataApplier.ApplyIfMissing(manga, external);

        AssertEqual(
            failures,
            3,
            manga.Volumes[0].TotalChapters,
            "volume 1 takes its real chapter count"
        );
        AssertEqual(
            failures,
            5,
            manga.Volumes[1].TotalChapters,
            "volume 2 takes its real chapter count"
        );

        // A count the user typed is not the seed, so it must survive the next provider pass.
        manga.Volumes[0].ApplyEdits(currentPage: null, totalPages: null, currentChapter: null, totalChapters: 11);
        MediaMetadataApplier.ApplyIfMissing(manga, external);
        AssertEqual(
            failures,
            11,
            manga.Volumes[0].TotalChapters,
            "a chapter count the user typed is not overwritten"
        );
    }

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
        public Task<string?> SaveCoverAsync(string url, Guid mediaId, CancellationToken ct) =>
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
        AssertEqual(
            failures,
            374,
            manga.Volumes[0].TotalChapters,
            "stub volume inherits chapter count"
        );
    }

    private static void CheckMangaGapEnrichmentDoesNotOverwrite(List<string> failures)
    {
        var manga = new Manga
        {
            Title = "Berserk",
            TotalChapters = 100,
            Author = "User typed this",
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
        AssertEqual(failures, "A dark fantasy epic", manga.Notes, "enrich fills empty notes");
    }

    private static void CheckOverwriteRefresh(List<string> failures)
    {
        var book = new Book
        {
            Title = "Old title",
            Author = string.Empty,
            TotalPages = 100,
            CurrentPage = 50,
        };
        var external = new ExternalMediaDto
        {
            ExternalId = "42",
            Title = "New title",
            Type = "book",
            TotalCount = 321,
            Author = "Someone Else",
        };

        MediaMetadataApplier
            .ApplyOverwriteAsync(book, external, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter()
            .GetResult();

        AssertEqual(failures, "New title", book.Title, "refresh overwrites the title");
        AssertEqual(failures, 321, book.TotalPages, "refresh overwrites the page count");
        AssertEqual(failures, "Someone Else", book.Author, "refresh overwrites the author");
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

    private static void CheckVolumeProgressStepper(List<string> failures)
    {
        AssertEqual(
            failures,
            MediaStatus.Completed,
            ProgressStepperRules.ResolveVolumeStatus(
                currentPage: 0,
                totalPages: 0,
                currentChapter: 40,
                totalChapters: 40
            ),
            "finishing the chapters completes the volume"
        );

        AssertEqual(
            failures,
            MediaStatus.Completed,
            ProgressStepperRules.ResolveVolumeStatus(
                currentPage: 200,
                totalPages: 200,
                currentChapter: 0,
                totalChapters: 0
            ),
            "finishing the pages completes the volume"
        );

        AssertEqual(
            failures,
            MediaStatus.InProgress,
            ProgressStepperRules.ResolveVolumeStatus(
                currentPage: 3,
                totalPages: 200,
                currentChapter: 0,
                totalChapters: 0
            ),
            "a partial read is in progress"
        );

        AssertEqual(
            failures,
            MediaStatus.Planned,
            ProgressStepperRules.ResolveVolumeStatus(
                currentPage: 0,
                totalPages: 200,
                currentChapter: 0,
                totalChapters: 0
            ),
            "an untouched volume stays planned"
        );
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

    private static void CheckPlaceholderVolumes(List<string> failures)
    {
        var request = new CreateMediaRequest
        {
            Type = "manga",
            Title = "Naruto",
            TotalChapters = 700,
            TotalVolumes = 4,
        };
        var manga = new Manga { Title = "Naruto" };

        MediaCollectionSeeder.SeedPlaceholderVolumes(manga, request);

        AssertEqual(failures, 4, manga.Volumes.Count, "one stub per requested volume");
        AssertEqual(
            failures,
            175,
            manga.Volumes[0].TotalChapters,
            "chapters split evenly across volumes"
        );
        AssertEqual(failures, 4, manga.TotalVolumes, "total volume count is recorded");
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

    private sealed class NoOpImageStorage : IImageStorageService
    {
        public Task<string?> SaveCoverAsync(
            string externalUrl,
            Guid itemId,
            CancellationToken ct = default
        ) => Task.FromResult<string?>(externalUrl);

        public void DeleteCover(string? localCoverUrl) { }

        public void DeleteMediaFolder(Guid mediaId) { }
    }
}
