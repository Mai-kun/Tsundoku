using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.History.GetHistoryEvents;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateProgress;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Security;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace MediaTracker.Tests;

public class RemoteIpStartupFilter : IStartupFilter
{
    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
    {
        return app =>
        {
            app.Use(async (context, nextMiddleware) =>
            {
                if (context.Request.Headers.TryGetValue("X-Test-Remote-IP", out var ipVal)
                    && IPAddress.TryParse(ipVal.ToString(), out var parsedIp))
                {
                    context.Connection.RemoteIpAddress = parsedIp;
                }
                await nextMiddleware();
            });
            next(app);
        };
    }
}

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _dbPath;

    public CustomWebApplicationFactory()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"tsundoku_test_{Guid.NewGuid():N}.db");
        Environment.SetEnvironmentVariable("HEADLESS", "true");
        Environment.SetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER", "true");
        Environment.SetEnvironmentVariable("ConnectionStrings__DefaultConnection", $"Data Source={_dbPath}");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.AddTransient<IStartupFilter, RemoteIpStartupFilter>();
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            try
            {
                if (File.Exists(_dbPath)) File.Delete(_dbPath);
                var shm = _dbPath + "-shm";
                if (File.Exists(shm)) File.Delete(shm);
                var wal = _dbPath + "-wal";
                if (File.Exists(wal)) File.Delete(wal);
            }
            catch
            {
                // Best-effort cleanup
            }
        }
    }
}

public class ApiIntegrationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public ApiIntegrationTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Flow1_CreateMedia_And_GetMediaById_ShouldWork()
    {
        var request = new CreateMediaRequest
        {
            Type = "book",
            Title = "The Name of the Wind",
            Author = "Patrick Rothfuss",
            TotalPages = 662,
            Status = MediaStatus.Planned,
            Score = 9,
            Notes = "Favorite fantasy book"
        };

        var postResponse = await _client.PostAsJsonAsync("/api/media", request);
        postResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var created = await postResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        created.Should().NotBeNull();
        created!.Id.Should().NotBeEmpty();
        created.Title.Should().Be("The Name of the Wind");
        created.Type.Should().Be("book");

        var getResponse = await _client.GetAsync($"/api/media/{created.Id}");
        getResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var fetched = await getResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        fetched.Should().NotBeNull();
        fetched!.Id.Should().Be(created.Id);
        fetched.Title.Should().Be("The Name of the Wind");
        fetched.Score.Should().Be(9);
    }

    [Fact]
    public async Task Flow2_UpdateMediaStatus_WithDropReasonAndNotes_ShouldSaveFields()
    {
        // 1. Create a media item
        var createRequest = new CreateMediaRequest
        {
            Type = "movie",
            Title = "Boring Movie",
            DurationMinutes = 110,
            Status = MediaStatus.InProgress,
        };
        var createResponse = await _client.PostAsJsonAsync("/api/media", createRequest);
        var created = await createResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        created.Should().NotBeNull();

        // 2. Put status update with DropReason and DropNotes
        var updateRequest = new UpdateStatusRequest
        {
            Status = MediaStatus.Dropped,
            DropReason = "bad_pacing",
            DropNotes = "Stopped watching at 45 minutes because of slow plot"
        };

        var putResponse = await _client.PutAsJsonAsync($"/api/media/{created!.Id}/status", updateRequest);
        putResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        // 3. Verify fields persisted
        var getResponse = await _client.GetAsync($"/api/media/{created.Id}");
        var updated = await getResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        updated.Should().NotBeNull();
        updated!.Status.Should().Be(MediaStatus.Dropped);
        updated.DropReason.Should().Be("bad_pacing");
        updated.DropNotes.Should().Be("Stopped watching at 45 minutes because of slow plot");
    }

    [Fact]
    public async Task Flow3_UpdateProgress_ShouldUpdateProgressAndRecordHistoryEvent()
    {
        // 1. Create a manga
        var createRequest = new CreateMediaRequest
        {
            Type = "manga",
            Title = "Chainsaw Man",
            TotalChapters = 180,
            Status = MediaStatus.InProgress,
        };
        var createResponse = await _client.PostAsJsonAsync("/api/media", createRequest);
        var created = await createResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        created.Should().NotBeNull();

        // 2. Update progress to chapter 50
        var progressRequest = new UpdateProgressRequest { CurrentProgress = 50 };
        var putResponse = await _client.PutAsJsonAsync($"/api/media/{created!.Id}/progress", progressRequest);
        putResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

        // 3. Verify manga current progress
        var getResponse = await _client.GetAsync($"/api/media/{created.Id}");
        var updated = await getResponse.Content.ReadFromJsonAsync<MediaDetailDto>(JsonOptions);
        updated.Should().NotBeNull();
        updated!.CurrentChapter.Should().Be(50);

        // 4. Verify history event was recorded for this media item
        var historyResponse = await _client.GetAsync($"/api/history?mediaId={created.Id}");
        historyResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var historyEvents = await historyResponse.Content.ReadFromJsonAsync<List<HistoryEventDto>>(JsonOptions);
        historyEvents.Should().NotBeNull();
        historyEvents.Should().NotBeEmpty();
        historyEvents!.Should().Contain(e => e.MediaId == created.Id);
    }

    [Fact]
    public async Task Flow4_GetAdvancedStats_ShouldReturnOkWithValidDto()
    {
        var response = await _client.GetAsync("/api/media/stats/advanced");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var stats = await response.Content.ReadFromJsonAsync<AdvancedStatsDto>(JsonOptions);
        stats.Should().NotBeNull();
        stats!.TotalTitles.Should().BeGreaterThanOrEqualTo(0);
        stats.ScoreDistribution.Should().NotBeNull();
    }

    [Fact]
    public async Task Flow5_ApiKeyAuthMiddleware_ShouldAuthenticateRemoteRequestsCorrectly()
    {
        var remoteIp = "192.168.1.100";
        var testToken = "tsk_live_test_integration_token_abcdef123456";

        // Register token in database
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var tokenHash = ApiTokenHelper.ComputeHash(testToken);
            if (!db.ApiTokens.Any(t => t.TokenHash == tokenHash))
            {
                db.ApiTokens.Add(new ApiToken
                {
                    Name = "Integration Test Token",
                    TokenHash = tokenHash,
                    TokenPrefix = "tsk_live_",
                    CreatedAt = DateTime.UtcNow
                });
                await db.SaveChangesAsync();
            }
        }

        // 1. Request from remote IP without token -> 401 Unauthorized
        using var unauthReq = new HttpRequestMessage(HttpMethod.Get, "/api/media/stats/advanced");
        unauthReq.Headers.Add("X-Test-Remote-IP", remoteIp);
        var unauthResponse = await _client.SendAsync(unauthReq);
        unauthResponse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        // 2. Request from remote IP with invalid token -> 401 Unauthorized
        using var invalidReq = new HttpRequestMessage(HttpMethod.Get, "/api/media/stats/advanced");
        invalidReq.Headers.Add("X-Test-Remote-IP", remoteIp);
        invalidReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "invalid_token_123");
        var invalidResponse = await _client.SendAsync(invalidReq);
        invalidResponse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        // 3. Request from remote IP with valid Bearer token -> 200 OK
        using var authReq = new HttpRequestMessage(HttpMethod.Get, "/api/media/stats/advanced");
        authReq.Headers.Add("X-Test-Remote-IP", remoteIp);
        authReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", testToken);
        var authResponse = await _client.SendAsync(authReq);
        authResponse.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
