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
        if (response.StatusCode != HttpStatusCode.OK)
        {
            var body = await response.Content.ReadAsStringAsync();
            throw new Xunit.Sdk.XunitException($"GET /api/media?{query} -> {(int)response.StatusCode}: {body}");
        }

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

    // ---- Вынесенные подкатегории навигации (промоутед: «Комиксы», «Ранобэ») ----

    private const string ComicsConfig = """
        {"categories":[{"id":"comics","label":"Комиксы","icon":"bookmark","parentType":"Book","matchKind":"format","matchValue":"comics"}]}
        """;

    private const string GenreComicsConfig = """
        {"categories":[{"id":"comics","label":"Комиксы","icon":"bookmark","parentType":"Book","matchKind":"genre","matchValue":"Комиксы"}]}
        """;

    private async Task SaveNavigationCategoriesAsync(string json)
    {
        var response = await _client.PutAsync(
            "/api/settings/navigation-categories",
            new StringContent(json, System.Text.Encoding.UTF8, "application/json"));
        if (response.StatusCode != HttpStatusCode.OK)
        {
            var body = await response.Content.ReadAsStringAsync();
            throw new Xunit.Sdk.XunitException(
                $"PUT /api/settings/navigation-categories -> {(int)response.StatusCode}: {body}");
        }
    }

    private async Task ClearNavigationCategoriesAsync()
    {
        await SaveNavigationCategoriesAsync("""{"categories":[]}""");
    }

    private async Task AddBookAsync(Guid id, string title, string? format, string? genres = null)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.MediaItems.Add(new Book { Id = id, Title = title, Author = "A", Format = format, Genres = genres });
        await db.SaveChangesAsync();
    }

    [Fact]
    public async Task PromotedSubcategory_ShouldShowComics_AndExcludeThemFromBooks()
    {
        var comicId = Guid.NewGuid();
        var novelId = Guid.NewGuid();
        try
        {
            await AddBookAsync(comicId, "Comics Title", "comics");
            await AddBookAsync(novelId, "Plain Book", "book");
            await SaveNavigationCategoriesAsync(ComicsConfig);

            // Вынесенная категория показывает комиксы...
            var comics = await GetMediaAsync("type=book&sub=comics");
            comics.Should().Contain(i => i.Id == comicId);
            comics.Should().NotContain(i => i.Id == novelId);

            // ...и они исчезают из «Книг».
            var books = await GetMediaAsync("type=book");
            books.Should().Contain(i => i.Id == novelId);
            books.Should().NotContain(i => i.Id == comicId);
        }
        finally
        {
            await ClearNavigationCategoriesAsync();
        }
    }

    [Fact]
    public async Task DisablingPromotedSubcategory_ReturnsComicsToBooks()
    {
        var comicId = Guid.NewGuid();
        try
        {
            await AddBookAsync(comicId, "Return Comics", "comics");
            await SaveNavigationCategoriesAsync(ComicsConfig);

            var promoted = await GetMediaAsync("type=book&sub=comics");
            promoted.Should().Contain(i => i.Id == comicId);
            var booksWithPromotion = await GetMediaAsync("type=book");
            booksWithPromotion.Should().NotContain(i => i.Id == comicId);

            // Убираем «Комиксы» из сайдбара — элементы возвращаются в «Книги» без рестарта.
            await ClearNavigationCategoriesAsync();

            var booksAfterRemoval = await GetMediaAsync("type=book");
            booksAfterRemoval.Should().Contain(i => i.Id == comicId);
            // Подкатегории больше нет в конфигурации — запрос к ней даёт 404.
            (await _client.GetAsync("/api/media?type=book&sub=comics")).StatusCode
                .Should().Be(HttpStatusCode.NotFound);
        }
        finally
        {
            await ClearNavigationCategoriesAsync();
        }
    }

    [Fact]
    public async Task PromotedSubcategory_ByGenre_MatchesExactGenreElement()
    {
        var comicGenreId = Guid.NewGuid();
        var plainGenreId = Guid.NewGuid();
        try
        {
            // Жанр хранится comma-строкой: матчиться должен целый элемент, не подстрока.
            await AddBookAsync(comicGenreId, "Genre Comics", null, "Комиксы,Приключения");
            await AddBookAsync(plainGenreId, "Genre Other", null, "Приключения,Фэнтези");
            await SaveNavigationCategoriesAsync(GenreComicsConfig);

            var comics = await GetMediaAsync("type=book&sub=comics");
            comics.Should().Contain(i => i.Id == comicGenreId);
            comics.Should().NotContain(i => i.Id == plainGenreId);

            var books = await GetMediaAsync("type=book");
            books.Should().Contain(i => i.Id == plainGenreId);
            books.Should().NotContain(i => i.Id == comicGenreId);
        }
        finally
        {
            await ClearNavigationCategoriesAsync();
        }
    }

    [Fact]
    public async Task PromotedSubcategory_TotalCountHeader_MatchesSelection()
    {
        // БД фабрики общая между тестами: проверяем относительное поведение —
        // новые комиксы видны в sub=comics (и посчитаны в X-Total-Count), но
        // в родительской «Книгах» нет ни одного элемента с форматом comics.
        var comicId = Guid.NewGuid();
        var secondComicId = Guid.NewGuid();
        try
        {
            await AddBookAsync(comicId, "Comics One", "comics");
            await AddBookAsync(secondComicId, "Comics Two", "comics");
            await SaveNavigationCategoriesAsync(ComicsConfig);

            var response = await _client.GetAsync("/api/media?type=book&sub=comics");
            var header = int.Parse(response.Headers.GetValues("X-Total-Count").First());
            header.Should().BeGreaterOrEqualTo(2);
            var comics = (await response.Content.ReadFromJsonAsync<MediaListDto[]>(JsonOptions))!;
            comics.Should().Contain(i => i.Id == comicId);
            comics.Should().Contain(i => i.Id == secondComicId);

            var booksResponse = await _client.GetAsync("/api/media?type=book&limit=500");
            int.Parse(booksResponse.Headers.GetValues("X-Total-Count").First())
                .Should().NotBe(header, "комиксы не входят в счётчик «Книг»");
            var books = (await booksResponse.Content.ReadFromJsonAsync<MediaListDto[]>(JsonOptions))!;
            books.Should().NotContain(i => i.Format == "comics");
        }
        finally
        {
            await ClearNavigationCategoriesAsync();
        }
    }

    [Fact]
    public async Task UnknownSubcategory_Returns404_AndInvalidConfig_Returns400()
    {
        (await _client.GetAsync("/api/media?type=book&sub=nope")).StatusCode
            .Should().Be(HttpStatusCode.NotFound);

        var badParent = await _client.PutAsync(
            "/api/settings/navigation-categories",
            new StringContent(
                """
                {"categories":[{"id":"bad","label":"Bad","icon":"bookmark","parentType":"Shelf","matchKind":"genre","matchValue":"x"}]}
                """,
                System.Text.Encoding.UTF8,
                "application/json"));
        badParent.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var badFormatKind = await _client.PutAsync(
            "/api/settings/navigation-categories",
            new StringContent(
                """
                {"categories":[{"id":"bad2","label":"Bad","icon":"bookmark","parentType":"Game","matchKind":"format","matchValue":"x"}]}
                """,
                System.Text.Encoding.UTF8,
                "application/json"));
        badFormatKind.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
