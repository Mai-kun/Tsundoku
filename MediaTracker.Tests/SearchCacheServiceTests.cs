using System.Net;
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
    private static readonly byte[] PngBytes =
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];

    private string ImageDirectory => Path.Combine(_tempDir, "search_cache_images");

    /// <summary>
    /// Writes an image into the cache exactly the way the proxy endpoint does: stream into the
    /// temp FileStream, close it, atomic rename. No byte[] of the whole file is held by the API.
    /// </summary>
    private async Task<string> WriteCachedImageAsync(string url, byte[] bytes)
    {
        await using var temp = _service.OpenImageTempWriteStream(url);
        await temp.WriteAsync(bytes);
        await temp.FlushAsync();
        await temp.DisposeAsync();
        return _service.CommitImage(temp.Name, url);
    }

    [Fact]
    public async Task StreamingWrite_CommitsAtomically_AndStreamsBackTheSameBytes()
    {
        var url = "https://image.tmdb.org/t/p/w500/abc.jpg";

        var path = await WriteCachedImageAsync(url, PngBytes);

        path.Should().EndWith(".img");
        var freshPath = _service.TryGetFreshImagePath(url);
        freshPath.Should().NotBeNull();
        Path.GetFullPath(freshPath!).Should().Be(Path.GetFullPath(path));

        // The bytes on disk are exactly what the download wrote.
        var read = new MemoryStream();
        await using (var fs = new FileStream(freshPath!, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, useAsync: true))
        {
            await fs.CopyToAsync(read);
        }

        read.ToArray().Should().Equal(PngBytes);
        SearchCacheService.DetectImageContentType(read.ToArray().AsSpan()).Should().Be("image/png");

        // File name is pure SHA-256 hex + fixed extension: no traversal surface.
        var file = new DirectoryInfo(ImageDirectory).EnumerateFiles().Single(f => !f.Name.EndsWith(".tmp"));
        file.Name.Should().Be(SearchCacheService.GetImageFileName(url));
        file.Name.Should().MatchRegex("^[0-9a-f]{64}\\.img$");
    }

    [Fact]
    public void DetectImageContentType_SniffsKnownSignatures()
    {
        SearchCacheService.DetectImageContentType(PngBytes).Should().Be("image/png");
        SearchCacheService.DetectImageContentType([0xFF, 0xD8, 0xFF, 0xE0]).Should().Be("image/jpeg");
        SearchCacheService.DetectImageContentType("GIF89a"u8.ToArray()).Should().Be("image/gif");
        SearchCacheService.DetectImageContentType([1, 2, 3]).Should().Be("application/octet-stream");
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
    public async Task TryGetFreshImagePath_ExpiredFile_ReturnsNullAndDeletesIt()
    {
        var url = "https://cdn.example.com/stale.png";
        await WriteCachedImageAsync(url, PngBytes);

        File.SetLastWriteTimeUtc(
            Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(url)),
            DateTime.UtcNow - SearchCacheService.DefaultTtl - TimeSpan.FromMinutes(5));

        _service.TryGetFreshImagePath(url).Should().BeNull();
        File.Exists(Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(url))).Should().BeFalse();
    }

    [Fact]
    public async Task RemoveExpiredAsync_SweepsStaleImageFiles_KeepsFreshOnes()
    {
        var freshUrl = "https://cdn.example.com/fresh.png";
        var staleUrl = "https://cdn.example.com/stale.png";
        await WriteCachedImageAsync(freshUrl, PngBytes);
        await WriteCachedImageAsync(staleUrl, PngBytes);

        File.SetLastWriteTimeUtc(
            Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(staleUrl)),
            DateTime.UtcNow - SearchCacheService.DefaultTtl - TimeSpan.FromMinutes(5));

        await _service.RemoveExpiredAsync();

        _service.TryGetFreshImagePath(freshUrl).Should().NotBeNull();
        _service.TryGetFreshImagePath(staleUrl).Should().BeNull();

        var info = await _service.GetInfoAsync();
        info.ImageFileCount.Should().Be(1);
        info.ImageFileSizeBytes.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task SweepImageCache_OverBudget_EvictsOldestFilesDownToTarget()
    {
        // Separate service with a tiny budget (4 KB trigger, 3.2 KB target) to keep the test fast.
        using var budgeted = new SearchCacheService(new AppPaths(_tempDir, isDevelopment: true), imageCacheBudgetBytes: 4096);
        var urls = new[] { "https://cdn.example.com/a.png", "https://cdn.example.com/b.png", "https://cdn.example.com/c.png" };

        var bytes = new byte[2048];
        foreach (var (url, index) in urls.Select((u, i) => (u, i)))
        {
            await WriteCachedImageAsync(url, bytes);
            // Distinct ages make the LRU order deterministic: a is oldest, c is newest.
            File.SetLastWriteTimeUtc(
                Path.Combine(ImageDirectory, SearchCacheService.GetImageFileName(url)),
                DateTime.UtcNow.AddMinutes(-30 + index));
        }

        // 3 × 2 KB = 6 KB > 4 KB budget: the sweep must evict the oldest files until ≤ 3.2 KB.
        await budgeted.RemoveExpiredAsync();

        var survivors = new DirectoryInfo(ImageDirectory).EnumerateFiles().ToList();
        survivors.Should().HaveCount(1);
        survivors[0].Name.Should().Be(SearchCacheService.GetImageFileName(urls[2]), "the newest file survives");

        var info = await budgeted.GetInfoAsync();
        info.ImageFileSizeBytes.Should().BeLessOrEqualTo(4096 * 4 / 5);
    }

    [Fact]
    public async Task ClearAsync_RemovesImageCache_AndLeavesMediaLibraryIntact()
    {
        // A fake permanent-library file inside data/media/ that must survive the cache reset.
        var mediaFile = Path.Combine(_tempDir, "media", "some-item", "cover", "thumb.webp");
        Directory.CreateDirectory(Path.GetDirectoryName(mediaFile)!);
        await File.WriteAllTextAsync(mediaFile, "permanent cover");

        await _service.SetAsync(SearchCacheService.BuildKey("all", "book", "one"), SampleResults("One"));
        await WriteCachedImageAsync("https://cdn.example.com/cover.png", PngBytes);

        var before = await _service.GetInfoAsync();
        before.EntryCount.Should().Be(1);
        before.ImageFileCount.Should().Be(1);

        await _service.ClearAsync();

        var after = await _service.GetInfoAsync();
        after.EntryCount.Should().Be(0);
        after.ImageFileCount.Should().Be(0);
        after.ImageFileSizeBytes.Should().Be(0);
        _service.TryGetFreshImagePath("https://cdn.example.com/cover.png").Should().BeNull();
        File.Exists(mediaFile).Should().BeTrue("data/media/ must never be touched by the search cache");
    }

    // --- Single-flight downloader (streaming, no byte[] of the body) ---

    private sealed class FakeHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(responder(request));
    }

    private sealed class FakeHttpClientFactory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }

    /// <summary>An endless stream of zeros: simulates a CDN that never stops sending a body.</summary>
    private sealed class EndlessZeroStream : Stream
    {
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get; set; }

        public override int Read(byte[] buffer, int offset, int count)
        {
            Array.Clear(buffer, offset, count);
            return count;
        }

        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    [Fact]
    public async Task DownloadAndCacheImage_Success_StreamsIntoCacheFile()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StreamContent(new MemoryStream(PngBytes)),
        });
        var factory = new FakeHttpClientFactory(handler);

        var url = "https://cdn.example.com/ok.png";
        var download = await ProxyExternalImageEndpoint.DownloadAndCacheImageAsync(factory, _service, url);

        download.Success.Should().BeTrue();
        download.StatusCode.Should().Be(200);
        File.Exists(download.CachePath).Should().BeTrue();
        (await File.ReadAllBytesAsync(download.CachePath!)).Should().Equal(PngBytes);

        // No temp leftovers: the atomic rename consumed it.
        new DirectoryInfo(ImageDirectory).EnumerateFiles().Should().ContainSingle(f => f.Name.EndsWith(".img"));
    }

    [Fact]
    public async Task DownloadAndCacheImage_OversizedBody_Returns413_AndCachesNothing()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StreamContent(new EndlessZeroStream()),
        });
        var factory = new FakeHttpClientFactory(handler);

        var url = "https://cdn.example.com/huge.png";
        var download = await ProxyExternalImageEndpoint.DownloadAndCacheImageAsync(factory, _service, url);

        download.Success.Should().BeFalse();
        download.StatusCode.Should().Be(413);
        download.CachePath.Should().BeNull();

        // Nothing lands in the cache: neither the final file nor a ".tmp" leftover.
        Directory.EnumerateFiles(ImageDirectory, "*", SearchOption.TopDirectoryOnly)
            .Should().BeEmpty("an oversized download must not leave a temp file behind");
    }

    [Fact]
    public async Task DownloadAndCacheImage_UpstreamError_IsNotCached()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.NotFound));
        var factory = new FakeHttpClientFactory(handler);

        var url = "https://cdn.example.com/missing.png";
        var download = await ProxyExternalImageEndpoint.DownloadAndCacheImageAsync(factory, _service, url);

        download.Success.Should().BeFalse();
        download.StatusCode.Should().Be(404);
        download.CachePath.Should().BeNull();
        Directory.Exists(ImageDirectory).Should().BeFalse("no temp file was ever created for an upstream 404");
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
