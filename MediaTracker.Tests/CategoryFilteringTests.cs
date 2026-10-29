using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Category filtering over GET /api/media: media type is matched case-insensitively and the anime
/// flag treats NULL as false on both sides.
/// </summary>
public class CategoryFilteringTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly HttpClient _client;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public CategoryFilteringTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private async Task<MediaListDto[]> GetMediaAsync(string query)
    {
        var response = await _client.GetAsync($"/api/media?{query}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<MediaListDto[]>(JsonOptions))!;
    }

    private static string Id(Guid id) => id.ToString().ToUpperInvariant();

    [Fact]
    public async Task TypeFilter_ShouldMatchRegardlessOfStoredCase()
    {
        var mangaId = Guid.NewGuid();
        var movieId = Guid.NewGuid();

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.MediaItems.Add(new Manga { Id = mangaId, Title = "Lowercase Manga", Author = "A" });
            db.MediaItems.Add(new Movie { Id = movieId, Title = "Canonical Movie" });
            await db.SaveChangesAsync();
            await db.Database.ExecuteSqlRawAsync(
                $"UPDATE MediaItems SET MediaType = 'mAnGa' WHERE Id = '{Id(mangaId)}'");
        }

        var items = await GetMediaAsync("type=manga");

        items.Should().Contain(i => i.Id == mangaId && i.Type == "manga");
        items.Should().NotContain(i => i.Id == movieId);
    }

    [Fact]
    public async Task TypeAndIsAnimeFalse_ShouldReturnOnlyNonAnimeMovies_AndIgnoreNullFlags()
    {
        var nonAnimeId = Guid.NewGuid();
        var animeMovieId = Guid.NewGuid();
        var animeShowId = Guid.NewGuid();

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.MediaItems.Add(new Movie { Id = nonAnimeId, Title = "Plain Movie", IsAnime = false });
            db.MediaItems.Add(new Movie { Id = animeMovieId, Title = "Anime Movie", IsAnime = true });
            db.MediaItems.Add(new TvShow { Id = animeShowId, Title = "Anime Show", IsAnime = true });
            await db.SaveChangesAsync();
            // Null flags must count as "not anime" instead of being filtered out.
            await db.Database.ExecuteSqlRawAsync(
                $"UPDATE MediaItems SET Movie_IsAnime = NULL, MediaType = 'movie' WHERE Id = '{Id(nonAnimeId)}'");
        }

        var items = await GetMediaAsync("type=movie&isAnime=false");

        items.Should().Contain(i => i.Id == nonAnimeId);
        items.Should().NotContain(i => i.Id == animeMovieId);
        items.Should().NotContain(i => i.Id == animeShowId);
    }

    [Fact]
    public async Task IsAnimeTrue_ShouldReturnMovieAndTvShowFlags()
    {
        var animeMovieId = Guid.NewGuid();
        var animeShowId = Guid.NewGuid();
        var plainMovieId = Guid.NewGuid();

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.MediaItems.Add(new Movie { Id = animeMovieId, Title = "Flagged Anime Movie", IsAnime = true });
            db.MediaItems.Add(new TvShow { Id = animeShowId, Title = "Flagged Anime Show", IsAnime = true });
            db.MediaItems.Add(new Movie { Id = plainMovieId, Title = "Unflagged Movie", IsAnime = false });
            await db.SaveChangesAsync();
        }

        var items = await GetMediaAsync("isAnime=true");

        items.Should().Contain(i => i.Id == animeMovieId);
        items.Should().Contain(i => i.Id == animeShowId);
        items.Should().NotContain(i => i.Id == plainMovieId);
    }
}
