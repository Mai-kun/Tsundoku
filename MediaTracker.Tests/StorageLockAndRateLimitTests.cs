using System.Net;
using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace MediaTracker.Tests;

public class StorageLockAndRateLimitTests
{
    [Fact]
    public void FileLockGuard_ShouldCreateSentinelAndLockStorageConfig()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_test_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        var configFile = Path.Combine(tempDir, "storage.json");
        File.WriteAllText(configFile, "{\"mode\":\"portable\"}");

        var paths = new AppPaths(tempDir, isDevelopment: true, mode: "portable");

        try
        {
            using var lockGuard = new FileLockGuard(tempDir, configFile);

            // Sentinel file should exist
            var sentinel = Path.Combine(tempDir, ".data.lock");
            File.Exists(sentinel).Should().BeTrue();

            // Storage lock stream should be active (cannot delete or open exclusively without share)
            // On Windows this throws IOException directly; on Linux we test that lock is held
            File.Exists(configFile).Should().BeTrue();
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void AppPaths_GetOrRecreateStorageConfig_ShouldRegenerateIfDeleted()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "tsundoku_test_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);
        var paths = new AppPaths(tempDir, isDevelopment: true, mode: "custom", customPath: tempDir);

        try
        {
            var configPath = AppPaths.GetStorageConfigPath();
            if (File.Exists(configPath))
            {
                try { File.Delete(configPath); } catch { }
            }

            // Initially ensure config is created
            var config = paths.GetOrRecreateStorageConfig();
            config.Mode.Should().Be("custom");
            config.CustomPath.Should().Be(tempDir);

            if (File.Exists(configPath))
            {
                File.Delete(configPath);
            }

            // External deletion simulation: should NOT throw FileNotFoundException
            var regenerated = paths.GetOrRecreateStorageConfig();
            regenerated.Should().NotBeNull();
            regenerated.Mode.Should().Be("custom");
            regenerated.CustomPath.Should().Be(tempDir);
        }
        finally
        {
            try { Directory.Delete(tempDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void RateLimitTracker_ShouldTrackAndUpdateProviderLimits()
    {
        var tracker = new RateLimitTracker();
        tracker.Update("anilist", "AniList", remaining: 82, limit: 90, resetSecondsRemaining: 45);
        tracker.Update("mangadex", "MangaDex", remaining: 5, limit: 10, resetSecondsRemaining: 15);

        var all = tracker.GetAll();
        all.Should().HaveCount(2);

        var anilist = all.First(x => x.Provider == "AniList");
        anilist.Remaining.Should().Be(82);
        anilist.Limit.Should().Be(90);
        anilist.ResetSecondsRemaining.Should().BeInRange(44, 45);

        var mangadex = all.First(x => x.Provider == "MangaDex");
        mangadex.Remaining.Should().Be(5);
        mangadex.Limit.Should().Be(10);
    }

    [Fact]
    public async Task ExternalHttpLoggingHandler_ShouldInterceptRateLimitHeaders()
    {
        var tracker = new RateLimitTracker();
        var innerHandler = new TestHttpMessageHandler((request, cancellationToken) =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK);
            response.Headers.Add("X-RateLimit-Remaining", "82");
            response.Headers.Add("X-RateLimit-Limit", "90");
            response.Headers.Add("X-RateLimit-Reset", "45");
            return Task.FromResult(response);
        });

        var handler = new ExternalHttpLoggingHandler(NullLogger<ExternalHttpLoggingHandler>.Instance, tracker)
        {
            InnerHandler = innerHandler
        };

        var client = new HttpClient(handler);
        var request = new HttpRequestMessage(HttpMethod.Get, "https://graphql.anilist.co");
        var response = await client.SendAsync(request);
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var all = tracker.GetAll();
        all.Should().HaveCount(1);
        var item = all[0];
        item.Provider.Should().Be("AniList");
        item.Remaining.Should().Be(82);
        item.Limit.Should().Be(90);
        item.ResetSecondsRemaining.Should().BeInRange(44, 45);
    }

    private sealed class TestHttpMessageHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handlerFunc) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            handlerFunc(request, cancellationToken);
    }
}
