using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.Calendar;
using MediaTracker.Server.Features.Seasons.UpdateSeasonProgress;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Thin-payload endpoints that unit tests cannot reach: calendar aggregation, season progress,
/// creator summary, reading settings and media list filtering surface.
/// </summary>
public class EndpointsIntegrationTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public EndpointsIntegrationTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private static TvShow SeedShow(string title, int totalEpisodes, int currentEpisode)
    {
        var show = new TvShow { Title = title, Status = MediaStatus.InProgress };
        show.Seasons.Add(new TvSeason { SeasonNumber = 1, Title = title + " S1", TotalEpisodes = totalEpisodes, CurrentEpisode = currentEpisode, EpisodesData = "[]" });
        return show;
    }

    [Fact]
    public async Task Calendar_ShouldRejectInvertedRange()
    {
        var response = await _client.GetAsync("/api/media/calendar?from=2026-01-10&to=2026-01-01");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Calendar_ShouldReturnAirDatesAndPlannedReleases()
    {
        // seed through the scope: a show with a dated episode in the current month and a planned title
        var showId = Guid.NewGuid();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var show = SeedShow("Seasonal Show", totalEpisodes: 12, currentEpisode: 2);
            show.Id = showId;
            show.Seasons.Single().EpisodesData = $$"""[{"Number":1,"Title":"Ep","AirDate":"{{DateTime.UtcNow:yyyy-MM-dd}}"}]""";
            db.MediaItems.Add(show);
            db.MediaItems.Add(new Movie { Title = "Upcoming Films", Status = MediaStatus.Planned, ReleaseDate = DateTime.UtcNow });
            await db.SaveChangesAsync();
        }

        var response = await _client.GetAsync("/api/media/calendar");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var schedule = await response.Content.ReadFromJsonAsync<CalendarScheduleDto>(JsonOptions);
        schedule.Should().NotBeNull();
        var kinds = schedule!.Days.SelectMany(d => d.Items).Select(i => i.Kind).ToList();
        kinds.Should().Contain("air_date");
        kinds.Should().Contain("release");
        schedule.Days.SelectMany(d => d.Items).Should().Contain(i => i.MediaId == showId && i.Kind == "air_date");
    }

    [Fact]
    public async Task SeasonProgress_ShouldClampAndPropagateStatusToParentShow()
    {
        var seasonId = Guid.NewGuid();
        var showId = Guid.NewGuid();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var show = SeedShow("Show", totalEpisodes: 12, currentEpisode: 0);
            show.Id = showId;
            show.Seasons.Single().Id = seasonId;
            db.MediaItems.Add(show);
            await db.SaveChangesAsync();
        }

        var response = await _client.PutAsJsonAsync($"/api/seasons/{seasonId}/progress", new UpdateSeasonProgressRequest { CurrentEpisode = 99 });
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var reloaded = db.TvShows.AsNoTracking().Include(s => s.Seasons).Single(s => s.Id == showId);
            reloaded.Seasons.Single().CurrentEpisode.Should().Be(12);
            reloaded.Status.Should().Be(MediaStatus.Completed);
        }

        // unknown season -> 404 problem detail
        var missing = await _client.PutAsJsonAsync($"/api/seasons/{Guid.NewGuid()}/progress", new UpdateSeasonProgressRequest { CurrentEpisode = 1 });
        missing.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task MediaList_ShouldFilterSearchSortThroughHttp()
    {
        var response = await _client.GetAsync("/api/media/?type=movie&sortBy=title&sortOrder=asc&search=NoMatchAtAll");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        // unknown type degrades to an empty list, not a 500
        var bad = await _client.GetAsync("/api/media/?type=banana");
        bad.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task UpdateMedia_ShouldPersistMetadataEdits()
    {
        Guid id;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var item = new VideoGame { Title = "Portal", Platform = "PC", Score = 6 };
            db.MediaItems.Add(item);
            await db.SaveChangesAsync();
            id = item.Id;
        }

        var put = await _client.PutAsJsonAsync($"/api/media/{id}", new { Title = "Portal (edited)", Score = 9, Notes = "cake" });
        put.StatusCode.Should().Be(HttpStatusCode.OK);

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var reloaded = db.MediaItems.AsNoTracking().Single(m => m.Id == id);
            reloaded.Title.Should().Be("Portal (edited)");
            reloaded.Score.Should().Be(9);
            reloaded.Notes.Should().Be("cake");
        }
    }

    [Fact]
    public async Task ResetAndSourcesAndOtherEndpoints_ShouldRespond()
    {
        (await _client.GetAsync("/api/media/creator-summary?name=Rothfuss&role=author")).StatusCode
            .Should().Be(HttpStatusCode.OK);
        (await _client.GetAsync("/api/media/stats/taste-profile")).StatusCode
            .Should().Be(HttpStatusCode.OK);
        (await _client.GetAsync("/api/media/pending-matches")).StatusCode
            .Should().Be(HttpStatusCode.OK);
        (await _client.PostAsync($"/api/media/dismiss-all-matches", null)).StatusCode
            .Should().Be(HttpStatusCode.OK);
        (await _client.PostAsync($"/api/media/resolve-all-by-priority", null)).StatusCode
            .Should().NotBe(HttpStatusCode.InternalServerError);
    }
}
