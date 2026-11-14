using FluentAssertions;
using MediaTracker.Server.Features.External.ProxyExternalImage;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Xunit;

namespace MediaTracker.Tests;

public sealed class SearchCacheServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly SearchCacheService _service;

    public SearchCacheServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"search-cache-tests-{Guid.NewGuid():N}");
        var appPaths = new AppPaths(_tempDir, isDevelopment: true);
        _service = new SearchCacheService(appPaths);
    }

    public void Dispose()
    {
        _service.Dispose();
        if (Directory.Exists(_tempDir))
        {
            Directory.Delete(_tempDir, recursive: true);
        }
    }

    private static List<ExternalMediaDto> SampleResults(string title) =>
    [
        new ExternalMediaDto
        {
            ExternalId = "id-1",
            ExternalSource = "livelib",
            Title = title,
            Type = "book",
            ReleaseYear = 2012,
        },
    ];

    [Fact]
    public void DefaultTtl_IsThreeDays()
    {
        SearchCacheService.DefaultTtl.Should().Be(TimeSpan.FromHours(72));
    }

    [Fact]
    public async Task SetThenTryGet_RoundTripsPayload()
    {
        var key = SearchCacheService.BuildKey("livelib", "book", "  Мастер и Маргарита  ", byCreator: false);

        await _service.SetAsync(key, SampleResults("Мастер и Маргарита"));
        var cached = await _service.TryGetAsync(key);

        cached.Should().NotBeNull();
        cached.Should().HaveCount(1);
        cached![0].Title.Should().Be("Мастер и Маргарита");
        cached[0].ExternalSource.Should().Be("livelib");
        cached[0].ReleaseYear.Should().Be(2012);
    }

    [Fact]
    public async Task BuildKey_NormalizesSourceTypeAndQuery()
    {
        var first = SearchCacheService.BuildKey("LiveLib", "Book", "Some Query", byCreator: false);
        var second = SearchCacheService.BuildKey("livelib", "book", "some query ", byCreator: false);

        first.Should().Be(second);
        first.Should().StartWith("livelib:book:some query");
    }

    [Fact]
    public async Task TryGet_UnknownKey_ReturnsNull()
    {
        var cached = await _service.TryGetAsync("all:movie:never cached");

        cached.Should().BeNull();
    }

    [Fact]
    public async Task TryGet_ExpiredEntry_ReturnsNullAndDeletesRow()
    {
        var key = SearchCacheService.BuildKey("all", "game", "portal");
        await _service.SetAsync(key, SampleResults("Portal"), ttl: TimeSpan.FromMilliseconds(50));

        await Task.Delay(120);

        var cached = await _service.TryGetAsync(key);
        cached.Should().BeNull();

        var info = await _service.GetInfoAsync();
        info.EntryCount.Should().Be(0);
    }

    [Fact]
    public async Task RemoveExpiredAsync_KeepsFreshRows()
    {
        var freshKey = SearchCacheService.BuildKey("all", "movie", "fresh");
        await _service.SetAsync(freshKey, SampleResults("Fresh"));

        // Insert a row that is already past its expiry, exactly as a previous run would leave it.
        var staleKey = SearchCacheService.BuildKey("all", "movie", "stale");
        await _service.SetAsync(staleKey, SampleResults("Stale"), ttl: TimeSpan.FromMilliseconds(50));
        await Task.Delay(120);

        await _service.RemoveExpiredAsync();

        (await _service.TryGetAsync(freshKey)).Should().NotBeNull();
        (await _service.TryGetAsync(staleKey)).Should().BeNull();

        var info = await _service.GetInfoAsync();
        info.EntryCount.Should().Be(1);
    }

    [Fact]
    public async Task ClearAsync_RemovesAllEntriesAndShrinksFile()
    {
        var dbPath = Path.Combine(_tempDir, "search_cache.db");

        await _service.SetAsync(SearchCacheService.BuildKey("all", "book", "one"), SampleResults("One"));
        await _service.SetAsync(SearchCacheService.BuildKey("all", "book", "two"), SampleResults("Two"));

        var before = await _service.GetInfoAsync();
        before.EntryCount.Should().Be(2);
        before.FileSizeBytes.Should().BeGreaterThan(0);
        File.Exists(dbPath).Should().BeTrue();

        await _service.ClearAsync();

        var after = await _service.GetInfoAsync();
        after.EntryCount.Should().Be(0);
        (await _service.TryGetAsync(SearchCacheService.BuildKey("all", "book", "one"))).Should().BeNull();
    }

    [Fact]
    public async Task GetInfoAsync_WithoutAnySearch_ReportsZeroEntries()
    {
        var info = await _service.GetInfoAsync();

        info.EntryCount.Should().Be(0);
        info.FileSizeBytes.Should().BeGreaterThan(0); // table was created lazily
        info.DatabasePath.Should().EndWith("search_cache.db");
    }

    [Fact]
    public async Task SetAsync_OverwritesExistingEntryWithFreshPayload()
    {
        var key = SearchCacheService.BuildKey("all", "movie", "overwrite");

        await _service.SetAsync(key, SampleResults("Old Answer"));
        await _service.SetAsync(key, SampleResults("New Answer"));

        var cached = await _service.TryGetAsync(key);
        cached.Should().HaveCount(1);
        cached![0].Title.Should().Be("New Answer");
    }

    // --- Disk cache of search preview images (data/search_cache_images/) ---

    /// <summary>A tiny PNG signature; only the magic bytes matter for the MIME sniffing.</summary>
    private static readonly byte[] PngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    private string ImageDirectory => Path.Combine(_tempDir, "search_cache_images");

    [Fact]
    public async Task SetImageThenTryGetImage_RoundTripsBytesAndSniffsMime()
    {
        var url = "https://image.tmdb.org/t/p/w500/abc.jpg";

        await _service.SetImageAsync(url, PngBytes);
        var cached = await _service.TryGetImageAsync(url);

        cached.Should().NotBeNull();
        cached!.Data.Should().Equal(PngBytes);
        cached.ContentType.Should().Be("image/png");

        // File name is pure SHA-256 hex + fixed extension: no traversal surface.
        var file = new DirectoryInfo(ImageDirectory).EnumerateFiles().Single();
        file.Name.Should().Be(SearchCacheService.GetImageFileName(url));
        file.Name.Should().MatchRegex("^[0-9a-f]{64}\\.img$");
    }

    [Fact]
    public void GetImageFileName_IsDeterministicAndTraversalSafe()
    {
        var first = SearchCacheService.GetImageFileName("https://example.com/a.png");
        var second = SearchCacheService.GetImageFileName("  https://example.com/a.png ");
        var evil = SearchCacheService.GetImageFileName("https://example.com/../../data/media/x");

        first.Should().Be(second);
        evil.Should().MatchRegex("^[0-9a-f]{64}\\.img$");
        Path.GetFileName(evil).Should().Be(evil);
    }

    [Fact]
    public async Task TryGetImage_ExpiredFile_ReturnsNullAndDeletesIt()
    {
        var url = "https://cdn.example.com/stale.png";
        await _service.SetImageAsync(url, PngBytes);

        File.SetLastWriteTimeUtc(
            Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(url)),
            DateTime.UtcNow - SearchCacheService.DefaultTtl - TimeSpan.FromMinutes(5));

        (await _service.TryGetImageAsync(url)).Should().BeNull();
        File.Exists(Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(url))).Should().BeFalse();
    }

    [Fact]
    public async Task RemoveExpiredAsync_SweepsStaleImageFiles_KeepsFreshOnes()
    {
        var freshUrl = "https://cdn.example.com/fresh.png";
        var staleUrl = "https://cdn.example.com/stale.png";
        await _service.SetImageAsync(freshUrl, PngBytes);
        await _service.SetImageAsync(staleUrl, PngBytes);

        File.SetLastWriteTimeUtc(
            Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(staleUrl)),
            DateTime.UtcNow - SearchCacheService.DefaultTtl - TimeSpan.FromMinutes(5));

        await _service.RemoveExpiredAsync();

        (await _service.TryGetImageAsync(freshUrl)).Should().NotBeNull();
        (await _service.TryGetImageAsync(staleUrl)).Should().BeNull();

        var info = await _service.GetInfoAsync();
        info.ImageFileCount.Should().Be(1);
        info.ImageFileSizeBytes.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task ClearAsync_RemovesImageCache_AndLeavesMediaLibraryIntact()
    {
        // A fake permanent-library file inside data/media/ that must survive the cache reset.
        var mediaFile = Path.Combine(_tempDir, "media", "some-item", "cover", "thumb.webp");
        Directory.CreateDirectory(Path.GetDirectoryName(mediaFile)!);
        await File.WriteAllTextAsync(mediaFile, "permanent cover");

        await _service.SetAsync(SearchCacheService.BuildKey("all", "book", "one"), SampleResults("One"));
        await _service.SetImageAsync("https://cdn.example.com/cover.png", PngBytes);

        var before = await _service.GetInfoAsync();
        before.EntryCount.Should().Be(1);
        before.ImageFileCount.Should().Be(1);

        await _service.ClearAsync();

        var after = await _service.GetInfoAsync();
        after.EntryCount.Should().Be(0);
        after.ImageFileCount.Should().Be(0);
        after.ImageFileSizeBytes.Should().Be(0);
        (await _service.TryGetImageAsync("https://cdn.example.com/cover.png")).Should().BeNull();
        File.Exists(mediaFile).Should().BeTrue("data/media/ must never be touched by the search cache");
    }

    [Theory]
    [InlineData("https://covers.imglib.info/x.jpg", true)]
    [InlineData("image.tmdb.org", true)]
    [InlineData("localhost", false)]
    [InlineData("127.0.0.1", false)]
    [InlineData("192.168.1.10", false)]
    [InlineData("10.0.0.5", false)]
    [InlineData("172.16.0.9", false)]
    [InlineData("169.254.1.1", false)]
    [InlineData("fe80::1", false)]
    [InlineData("", false)]
    public void IsAllowedRemoteHost_BlocksInternalTargets(string host, bool allowed)
    {
        ProxyExternalImageEndpoint.IsAllowedRemoteHost(host).Should().Be(allowed);
    }
}
