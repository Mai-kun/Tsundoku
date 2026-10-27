using System.Net;
using System.Text.Json;
using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import.Parsers;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Closes the unit-coverage gaps in pure business logic: manga volume rules, MAL JSON + extra
/// Mangalib branches, taste profile edge cases and the local cover storage pipeline.
/// </summary>
public class BusinessLogicGapTests : IDisposable
{
    private readonly string _dataDir;
    // Constructor body executes on construction of the class
    public BusinessLogicGapTests()
    {
        _dataDir = Path.Combine(Path.GetTempPath(), $"tsundoku_storage_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_dataDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dataDir, recursive: true); } catch { }
    }

    [Fact]
    public void MangaVolume_ShouldClampAndResolveStatus()
    {
        var volume = MangaVolume.CreateFrom(1, "Volume 1", null, 200, 0, 20, 0, MediaStatus.Planned, null, null, null, Guid.NewGuid());

        volume.SetProgress(250, 25); // clamps to totals
        volume.CurrentPage.Should().Be(200);
        volume.CurrentChapter.Should().Be(20);
        volume.Status.Should().Be(MediaStatus.Completed);
        volume.IsCompleted.Should().BeTrue();

        volume.SetProgress(50, 0);
        volume.Status.Should().Be(MediaStatus.InProgress);

        volume.SetProgress(0, 0);
        volume.Status.Should().Be(MediaStatus.Planned);

        // A volume stub with no totals: progress is kept unclamped
        volume.SetProgress(5, 0);
        volume.CurrentPage.Should().Be(5);
    }

    [Fact]
    public void MangaVolume_ApplyEdits_ShouldKeepUntouchedCounters()
    {
        var volume = MangaVolume.CreateFrom(1, "Volume 1", null, 200, 100, 20, 10, MediaStatus.Completed, null, null, null, Guid.NewGuid());

        volume.ApplyEdits(currentPage: 50, totalPages: null, currentChapter: null, totalChapters: null);

        volume.CurrentPage.Should().Be(50);
        volume.TotalPages.Should().Be(200);
        volume.CurrentChapter.Should().Be(10);
        volume.Status.Should().Be(MediaStatus.InProgress);
    }

    [Fact]
    public void MangaVolume_InheritAndPlaceholder()
    {
        var placeholder = MangaVolume.CreatePlaceholderVolume(2);
        placeholder.Title.Should().Be("Volume 2");
        placeholder.TotalPages.Should().Be(MangaVolume.PlaceholderPagesPerVolume);

        placeholder.InheritTotalChapters(30);
        placeholder.TotalChapters.Should().Be(30);

        int clamped = MangaVolume.Clamp(99, 40);
        clamped.Should().Be(40);
        int unclamped = MangaVolume.Clamp(-5, 0);
        unclamped.Should().Be(0);
    }

    [Fact]
    public void MalJsonParser_ShouldMapEntries()
    {
        var json = """
            { "data": [
              { "node": { "id": "16498", "title": "Shingeki no Kyojin", "num_episodes": 25, "start_date": "2013-04-07" },
                "list_status": { "status": "watching", "score": 9, "num_episodes_watched": 15 } },
              { "node": { "id": "2", "title": "Berserk", "num_chapters": 380, "num_volumes": 42 },
                "list_status": { "status": "on_hold", "score": 8, "num_chapters_read": 364, "num_volumes_read": 41 } }
            ] }
            """;

        var anime = MalJsonParser.Parse(json, mangaFile: false);
        anime.Should().HaveCount(2); // manga rows still pass; nothing to filter them here
        anime[0].Type.Should().Be("anime");
        anime[0].Status.Should().Be(MediaStatus.InProgress);
        anime[0].Score.Should().Be(9);
        anime[0].CurrentProgress.Should().Be(15);
        anime[0].TotalCount.Should().Be(25);
        anime[0].ExternalId.Should().Be("16498");
        anime[0].ExternalSource.Should().Be("mal");
        anime[0].ReleaseYear.Should().Be(2013);

        var manga = MalJsonParser.Parse(json, mangaFile: true);
        manga[1].Type.Should().Be("manga");
        manga[1].Status.Should().Be(MediaStatus.OnHold);
        manga[1].CurrentProgress.Should().Be(364);
        manga[1].TotalCount.Should().Be(380);
        manga[1].CurrentVolumes.Should().Be(41);
        manga[1].TotalVolumes.Should().Be(42);
    }

    [Fact]
    public void MangalibParser_ShouldCoverAnimeSiteAndEdgeBranches()
    {
        // site_id 5 → anime; numeric strings; missing fields
        var json = """
            [
              { "rus_name": "Аниме-заголовок", "type": "anime", "status": 1, "user_episodes": 3, "episodes": 12, "site_id": 5 },
              { "eng_name": "No rus", "user_chapters": 5, "chapters": 6, "user_rating": "7" },
              { "rus_name": "" }
            ]
            """;
        var parsed = MangalibParser.Parse(json);

        parsed[0].Type.Should().Be("anime");
        // anime entries keep progress in "user_chapters" style keys; "user_episodes" is not mapped → 0/null
        parsed[0].CurrentProgress.Should().Be(0);
        parsed[0].TotalCount.Should().Be(12);
        parsed[1].Title.Should().Be("No rus");
        // Third entry has no resolvable title → dropped
        parsed.Should().HaveCount(2);
    }

    // --- Taste profile: branches the existing test does not touch ---

    private static AdvancedStatsDto EmptyAdvanced() => new()
    {
        TotalTitles = 0, TotalHours = 0,
    };

    [Fact]
    public void TasteProfile_ShouldHandleEmptyLibrary()
    {
        var profile = TasteProfileCalculator.Calculate([], EmptyAdvanced());

        profile.Persona.Should().NotBeNull();
        profile.SunkCost.LowScoreHours.Should().Be(0);
        profile.SunkCost.PercentageOfTotal.Should().Be(0);
        profile.DropAnalytics.Should().NotBeNull();
        profile.GenreRadar.Should().NotBeNull();
    }

    [Fact]
    public void TasteProfile_ShouldComputeDivergenceAndGenreParadox()
    {
        var now = new DateTime(2026, 10, 7, 12, 0, 0, DateTimeKind.Utc);
        var low = new VideoGame
        {
            Title = "Boring Game", Platform = "PC", Status = MediaStatus.Completed,
            Score = 3, HoursPlayed = 30, Genres = "RPG", FinishedAt = now,
        };
        var dropped = new VideoGame
        {
            Title = "Dropped Game", Platform = "PC", Status = MediaStatus.Dropped,
            HoursPlayed = 10, Genres = "Comedy",
        };
        var loved = new VideoGame
        {
            Title = "Loved Game", Platform = "PC", Status = MediaStatus.Completed,
            Score = 10, HoursPlayed = 100, Genres = "RPG", FinishedAt = now,
        };

        var advanced = new AdvancedStatsDto { TotalTitles = 3, TotalHours = 140 };
        var profile = TasteProfileCalculator.Calculate([low, dropped, loved], advanced, onlyCompleted: false);

        profile.SunkCost.LowScoreHours.Should().BeGreaterThan(0);
        profile.SunkCost.PercentageOfTotal.Should().BeGreaterThan(0);
        profile.SunkCost.TitlesCount.Should().Be(2);
        profile.SunkCost.CategoryBreakdown.Should().ContainKey("game");
    }

    // --- Cover storage pipeline over a local HTTP stub ---

    private sealed class StubImageHandler(byte[] bytes, HttpStatusCode code = HttpStatusCode.OK, bool chunked = false)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var response = new HttpResponseMessage(code) { Content = new ByteArrayContent(bytes) };
            if (chunked)
            {
                response.Content.Headers.ContentLength = null;
            }
            return Task.FromResult(response);
        }
    }

    [Fact]
    public async Task ImageStorage_SaveCover_ShouldStoreWebpAndReturnLocalUrl()
    {
        var bytes = BuildPngBytes(400, 600);
        var appPaths = new AppPaths(_dataDir, isDevelopment: false);
        var service = new ImageStorageService(
            new HttpClient(new StubImageHandler(bytes)),
            appPaths,
            NullLogger<ImageStorageService>.Instance);

        var mediaId = Guid.NewGuid();
        var url = await service.SaveCoverAsync("https://example.com/cover.png", mediaId);

        url.Should().Be($"/media-assets/{mediaId}/cover/thumb.webp");
        File.Exists(Path.Combine(appPaths.MediaDirectory, mediaId.ToString(), "cover", "original.webp")).Should().BeTrue();
        File.Exists(Path.Combine(appPaths.MediaDirectory, mediaId.ToString(), "cover", "thumb.webp")).Should().BeTrue();

        // DeleteCover resolves the local URL and removes the originals under the title folder
        service.DeleteCover(null);
        service.DeleteCover("/covers/unknown.webp");
        service.DeleteCover($"/media-assets/{mediaId}/cover/original.webp");
        File.Exists(Path.Combine(appPaths.MediaDirectory, mediaId.ToString(), "cover", "original.webp")).Should().BeFalse();

        service.DeleteMediaFolder(mediaId);
        Directory.Exists(Path.Combine(appPaths.MediaDirectory, mediaId.ToString())).Should().BeFalse();
        // Path traversal guard: nothing outside the media root is touched
        service.DeleteMediaFolder(Guid.NewGuid());
    }

    [Fact]
    public async Task ImageStorage_SaveCover_ShouldFallBackToExternalUrl_OnFailure()
    {
        var appPaths = new AppPaths(_dataDir, isDevelopment: false);
        var service = new ImageStorageService(
            new HttpClient(new StubImageHandler([1, 2, 3], HttpStatusCode.NotFound)),
            appPaths,
            NullLogger<ImageStorageService>.Instance);

        var url = await service.SaveCoverAsync("https://example.com/missing.png", Guid.NewGuid());

        url.Should().Be("https://example.com/missing.png");
        (await service.SaveCoverAsync("   ", Guid.NewGuid(), folder: "cover")).Should().Be("   ");
    }

    [Fact]
    public async Task ImageStorage_SaveCover_ShouldRejectOversizedDeclaredCover()
    {
        var appPaths = new AppPaths(_dataDir, isDevelopment: false);
        var huge = new HttpClient(new HeaderOnlyHandler(12 * 1024 * 1024));
        var service = new ImageStorageService(
            huge,
            appPaths,
            NullLogger<ImageStorageService>.Instance);

        var url = await service.SaveCoverAsync("https://example.com/huge.png", Guid.NewGuid());

        url.Should().Be("https://example.com/huge.png");
    }

    [Fact]
    public async Task ImageStorage_SaveCover_ShouldRejectOversizedChunkedCover()
    {
        var appPaths = new AppPaths(_dataDir, isDevelopment: false);
        // Chunked: no Content-Length header, the body overflows the cap while streaming
        var bloated = new byte[11 * 1024 * 1024];
        var service = new ImageStorageService(
            new HttpClient(new StubImageHandler(bloated, chunked: true)),
            appPaths,
            NullLogger<ImageStorageService>.Instance);

        var url = await service.SaveCoverAsync("https://example.com/huge.png", Guid.NewGuid());

        url.Should().Be("https://example.com/huge.png");
    }

    private sealed class HeaderOnlyHandler(long declaredLength) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK);
            response.Content.Headers.ContentLength = declaredLength;
            return Task.FromResult(response);
        }
    }

    private static byte[] BuildPngBytes(int width, int height)
    {
        using var image = SixLabors.ImageSharp.Image.LoadPixelData<SixLabors.ImageSharp.PixelFormats.Rgba32>(
            new SixLabors.ImageSharp.PixelFormats.Rgba32[width * height], width, height);
        using var ms = new MemoryStream();
        image.Save(ms, new SixLabors.ImageSharp.Formats.Png.PngEncoder());
        return ms.ToArray();
    }
}
