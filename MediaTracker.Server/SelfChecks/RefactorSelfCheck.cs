using System.Text.Json;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Endpoints;
using MediaTracker.Server.Infrastructure;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Media;
using MediaTracker.Server.Services.Storage;

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
        CheckMissingMetadataDrivesCascade(failures);
        CheckPartialDatesDoNotBecomeJanFirst(failures);
        CheckEnrichFillsMovieDisplayGaps(failures);
        CheckExplicitClearFlags(failures);
        CheckAchievementsSurviveUpdate(failures);
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
    }
}
