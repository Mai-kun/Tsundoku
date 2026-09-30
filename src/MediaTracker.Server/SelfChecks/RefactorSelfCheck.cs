using System.Text.Json;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Media;
using MediaTracker.Server.Services.Storage;

namespace MediaTracker.Server.SelfChecks;

/// <summary>
/// Runnable assertion suite for the pure decision logic extracted out of the endpoint layer.
/// Run with: dotnet run --project src/MediaTracker.Server -- --selfcheck
/// </summary>
public static class RefactorSelfCheck
{
    public static int Run()
    {
        var failures = new List<string>();

        CheckSourceAliases(failures);
        CheckExternalUrlDetection(failures);
        CheckRatingsSerialization(failures);
        CheckMangaGapEnrichment(failures);
        CheckMangaGapEnrichmentDoesNotOverwrite(failures);
        CheckOverwriteRefresh(failures);
        CheckStatusTransitions(failures);
        CheckPlaceholderVolumes(failures);
        CheckReleaseStatusComputation(failures);
        CheckCoverSizeLimit(failures);

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
        AssertEqual(failures, "thetvdb", MediaMerger.NormalizeSourceKey("tvdb"), "tvdb short alias");
        AssertEqual(failures, "googlebooks", MediaMerger.NormalizeSourceKey("google"), "google alias");
        AssertEqual(failures, "tmdb", MediaMerger.NormalizeSourceKey("The Movie Database"), "tmdb long alias");
        AssertEqual(failures, "anilist", MediaMerger.NormalizeSourceKey("AniList"), "anilist alias");
        AssertEqual(failures, "unknownthing", MediaMerger.NormalizeSourceKey("UnknownThing"), "unknown falls through");

        AssertEqual(failures, "MyAnimeList", MediaMerger.GetCanonicalSourceName("mal"), "canonical exact");
        AssertEqual(failures, "TheTVDB", MediaMerger.GetCanonicalSourceName("thetvdb"), "canonical longest-wins");
        AssertEqual(failures, string.Empty, MediaMerger.GetCanonicalSourceName("  "), "canonical blank");
    }

    private static void CheckExternalUrlDetection(List<string> failures)
    {
        AssertTrue(failures, MediaMetadataApplier.IsExternalUrl("https://cdn.example/a.jpg"), "https is external");
        AssertTrue(failures, MediaMetadataApplier.IsExternalUrl("http://cdn.example/a.jpg"), "http is external");
        AssertFalse(failures, MediaMetadataApplier.IsExternalUrl("/covers/x.webp"), "local cover is not external");
        AssertFalse(failures, MediaMetadataApplier.IsExternalUrl("data:image/png;base64,AAA"), "data uri is not external");
        AssertFalse(failures, MediaMetadataApplier.IsExternalUrl(null), "null is not external");
    }

    private static void CheckRatingsSerialization(List<string> failures)
    {
        var json = MediaMetadataApplier.SerializeRatings(
        [
            new ExternalRatingDto { Source = "AniList", Rating = 8.5, Votes = 1200 }
        ]);

        using var document = JsonDocument.Parse(json);
        var first = document.RootElement[0];

        // The UI reads .score first, so the persisted key must be "score", not "rating".
        AssertEqual(failures, "AniList", first.GetProperty("source").GetString(), "rating source key");
        AssertEqual(failures, 8.5, first.GetProperty("score").GetDouble(), "rating score key");
        AssertEqual(failures, 1200, first.GetProperty("votes").GetInt32(), "rating votes key");
    }
    private static void CheckMangaGapEnrichment(List<string> failures)
    {
        var manga = new Manga { Title = "Berserk" };
        manga.Volumes.Add(new MangaVolume { Title = "Volume 1", VolumeNumber = 1, TotalChapters = 0 });
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Berserk",
            Type = "manga",
            Chapters = 374,
            Volumes = 41,
            Author = "Kentaro Miura"
        };

        var modified = MediaMetadataApplier.ApplyIfMissing(manga, external);

        AssertTrue(failures, modified, "enrich reports a change");
        AssertEqual(failures, 374, manga.TotalChapters, "manga chapters filled");
        AssertEqual(failures, 41, manga.TotalVolumes, "manga volumes filled");
        AssertEqual(failures, "Kentaro Miura", manga.Author, "manga author filled");
        AssertEqual(failures, 374, manga.Volumes[0].TotalChapters, "stub volume inherits chapter count");
    }

    private static void CheckMangaGapEnrichmentDoesNotOverwrite(List<string> failures)
    {
        var manga = new Manga { Title = "Berserk", TotalChapters = 100, Author = "User typed this" };
        var external = new ExternalMediaDto
        {
            ExternalId = "1",
            Title = "Berserk",
            Type = "manga",
            Chapters = 374,
            Author = "Kentaro Miura",
            Description = "A dark fantasy epic"
        };

        MediaMetadataApplier.ApplyIfMissing(manga, external);

        AssertEqual(failures, 100, manga.TotalChapters, "enrich must not overwrite a user value");
        AssertEqual(failures, "User typed this", manga.Author, "enrich must not overwrite a user author");
        AssertEqual(failures, "A dark fantasy epic", manga.Notes, "enrich fills empty notes");
    }

    private static void CheckOverwriteRefresh(List<string> failures)
    {
        var book = new Book { Title = "Old title", Author = string.Empty, TotalPages = 100, CurrentPage = 50 };
        var external = new ExternalMediaDto
        {
            ExternalId = "42",
            Title = "New title",
            Type = "book",
            TotalCount = 321,
            Author = "Someone Else"
        };

        MediaMetadataApplier.ApplyOverwriteAsync(book, external, new NoOpImageStorage(), CancellationToken.None)
            .GetAwaiter().GetResult();

        AssertEqual(failures, "New title", book.Title, "refresh overwrites the title");
        AssertEqual(failures, 321, book.TotalPages, "refresh overwrites the page count");
        AssertEqual(failures, "Someone Else", book.Author, "refresh overwrites the author");
    }
    private static void CheckStatusTransitions(List<string> failures)
    {
        var show = new TvShow { Title = "Frieren" };
        show.Seasons.Add(new TvSeason { Title = "Season 1", SeasonNumber = 1, TotalEpisodes = 12, CurrentEpisode = 4 });

        MediaStatusTransitions.Apply(show, MediaStatus.Completed);
        AssertEqual(failures, 12, show.Seasons[0].CurrentEpisode, "completing a show finishes the season");
        AssertEqual(failures, MediaStatus.Completed, show.Seasons[0].Status, "completing a show completes the season");

        var planned = new Book { Title = "Dune", Author = string.Empty, TotalPages = 412, CurrentPage = 300, StartedAt = DateTime.UtcNow };
        MediaStatusTransitions.Apply(planned, MediaStatus.Planned);
        AssertEqual(failures, null, planned.StartedAt, "moving back to planned clears the start date");
        AssertEqual(failures, 300, planned.CurrentPage, "moving to planned keeps progress");
    }

    private static void CheckPlaceholderVolumes(List<string> failures)
    {
        var request = new CreateMediaRequest { Type = "manga", Title = "Naruto", TotalChapters = 700, TotalVolumes = 4 };
        var manga = new Manga { Title = "Naruto" };

        MediaCollectionSeeder.SeedPlaceholderVolumes(manga, request);

        AssertEqual(failures, 4, manga.Volumes.Count, "one stub per requested volume");
        AssertEqual(failures, 175, manga.Volumes[0].TotalChapters, "chapters split evenly across volumes");
        AssertEqual(failures, 4, manga.TotalVolumes, "total volume count is recorded");
    }

    private static void CheckReleaseStatusComputation(List<string> failures)
    {
        var today = DateTime.UtcNow.Date;

        AssertEqual(failures, "NOT_YET_RELEASED", MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(30), null), "future release");
        AssertEqual(failures, "RELEASING", MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(-30), null), "ongoing release");
        AssertEqual(failures, "FINISHED", MediaItemFactory.ComputeReleaseStatusFromDates(today.AddDays(-300), today.AddDays(-1)), "ended release");
        AssertEqual(failures, null, MediaItemFactory.ComputeReleaseStatusFromDates(null, null), "unknown release");
    }

    /// <summary>
    /// A chunked cover response declares no Content-Length, so the byte cap has to hold on its own.
    /// </summary>
    private static void CheckCoverSizeLimit(List<string> failures)
    {
        using var withinLimit = new SizeLimitedStream(new MemoryStream(new byte[64]), 128);
        AssertEqual(failures, 64, withinLimit.Read(new byte[128]), "stream passes through a body under the limit");

        using var overLimit = new SizeLimitedStream(new MemoryStream(new byte[512]), 128);
        var threw = false;
        try
        {
            while (overLimit.Read(new byte[128]) > 0)
            {
            }
        }
        catch (OversizedCoverException)
        {
            threw = true;
        }

        AssertTrue(failures, threw, "stream rejects a body past the limit");
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
        public Task<string?> SaveCoverAsync(string externalUrl, Guid itemId, CancellationToken ct = default) =>
            Task.FromResult<string?>(externalUrl);

        public void DeleteCover(string? localCoverUrl)
        {
        }
    }
}
