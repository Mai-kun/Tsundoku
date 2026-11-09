using System.Net;
using FluentAssertions;
using MediaTracker.Server.Features.External.SearchExternal;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.LiveLib;
using Xunit;

namespace MediaTracker.Tests;

public class LiveLibMetadataProviderTests
{
    private sealed class StubHttpClientFactory(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name)
        {
            var delegatingHandler = new StubHttpMessageHandler(handler);
            return new HttpClient(delegatingHandler);
        }
    }

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            handler(request);
    }

    private const string SampleSearchHtml = """
        <div id="objects-block" class="objects-wrapper">
        <div class="object-wrapper object-edition ll-redirect" data-link="/book/1000000001-the-little-prince">
          <div class="object-info">
            <div class="brow-title"><a href="/book/1000000001" class="title">Маленький принц</a></div>
            <span class="book-author-item-1"><a class="description" href="/author/1">Антуан де Сент-Экзюпери</a></span>
            <div class="brow-genres"><a class="label-genre" href="/genre/Сказка">Сказка</a></div>
            <span class="rating-book"><span class="rating-value" itemprop="ratingValue">4,8</span></span>
          </div>
        </div>
        </div>
        """;

    private const string SampleBookHtml = """
        <html><head>
        <meta property="og:title" content="«Маленький принц». Автор: Антуан де Сент-Экзюпери">
        <meta property="og:description" content="Сказка-притча.">
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Book",
          "name": "Маленький принц",
          "author": [{"@type": "Person", "name": "Антуан де Сент-Экзюпери"}],
          "numberOfPages": 96,
          "datePublished": "1943-04-06"
        }
        </script>
        </head><body>
        <div class="DetailedInfo_DetailedInfoRow__XXovq"><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">Кол-во страниц: 96</p></div>
        <a href="/genre/Сказка">Сказка</a>
        </body></html>
        """;

    private const string GraphBookHtml = """
        <html><head>
        <meta property="og:title" content="«Маленький принц». Автор: Антуан де Сент-Экзюпери">
        <script id="orbitalis-book-card-schema" type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"BreadcrumbList"},
          {"@type":"Book","name":"Маленький принц",
           "isbn":"978-5-17-191259-8",
           "genre":["Сказки","Зарубежная классика","Зарубежные детские книги"],
           "inLanguage":"ru","bookFormat":"https://schema.org/Hardcover",
           "datePublished":"2026-01-01T00:00:00+03:00",
           "author":{"@type":"Person","name":"Антуан де Сент-Экзюпери"},
           "publisher":{"@type":"Organization","name":"АСТ"},
           "aggregateRating":{"@type":"AggregateRating","ratingValue":9,"ratingCount":89258,"bestRating":10}}
        ]}
        </script>
        </head><body>
        <span itemprop="description"><p>«Маленький принц» — самое знаменитое произведение Антуана де Сент-Экзюпери.</p></span>
        <div><p>Серия<!-- -->: </p><p>Шедевры иллюстрации</p></div>
        <div><p>Кол-во страниц: 160</p></div>
        <div><p>илл. Антонио Лоренте</p></div>
        </body></html>
        """;

    [Fact]
    public async Task GetDetailsAsync_MapsGraphRatingGenresIsbnDescriptionAndPages()
    {
        var factory = new StubHttpClientFactory(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(GraphBookHtml)
        }));

        var provider = new LiveLibMetadataProvider(factory);
        var details = await provider.GetDetailsAsync("1018210915", "Маленький принц", CancellationToken.None);

        details.Should().NotBeNull();
        details!.Rating.Should().Be(9.0);
        details.RatingVotes.Should().Be(89258);
        details.Ratings.Should().ContainSingle(rating =>
            rating.Source == "LiveLib" && rating.Rating == 9.0 && rating.Votes == 89258);
        details.Genres.Should().Equal("Сказки", "Зарубежная классика", "Зарубежные детские книги");
        details.Isbn.Should().Be("978-5-17-191259-8");
        details.Description.Should().Contain("самое знаменитое произведение").And.NotContain("Автор:");
        details.TotalCount.Should().Be(160);
        details.Tags.Should().Contain("Шедевры иллюстрации");
        details.Staff.Should().ContainSingle(member => member.Role == "Иллюстратор");
        details.ReleaseYear.Should().Be(2026);
        details.ReleaseDate.Should().Be("2026-01-01");
        details.OriginalLanguage.Should().Be("ru");
        details.Format.Should().Be("Твёрдый переплёт");
        details.Publisher.Should().Be("АСТ");
        details.Studio.Should().Be("АСТ");
    }

    [Fact]
    public void SourceDescriptor_ShouldHaveBookMediaTypeOnly()
    {
        var descriptor = LiveLibMetadataProvider.Source;
        descriptor.Id.Should().Be("livelib");
        descriptor.Name.Should().Be("LiveLib");
        descriptor.MediaTypes.Should().Equal(["book"]);
    }

    [Fact]
    public async Task SearchAsync_ShouldReturnItemsWithStrictBookType()
    {
        var factory = new StubHttpClientFactory(_ =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SampleSearchHtml)
            };
            return Task.FromResult(response);
        });

        var provider = new LiveLibMetadataProvider(factory);
        var results = await provider.SearchAsync("Маленький принц", CancellationToken.None);

        results.Should().NotBeEmpty();
        foreach (var item in results)
        {
            item.Type.Should().Be(MediaType.Book);
            item.Type.Should().Be("book");
            item.ExternalSource.Should().Be("LiveLib");
        }
    }

    [Fact]
    public async Task GetDetailsAsync_ShouldReturnItemWithStrictBookType()
    {
        var factory = new StubHttpClientFactory(req =>
        {
            var uri = req.RequestUri?.ToString() ?? string.Empty;
            var html = uri.Contains("/find/books/") ? SampleSearchHtml : SampleBookHtml;
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(html)
            };
            return Task.FromResult(response);
        });

        var provider = new LiveLibMetadataProvider(factory);
        var details = await provider.GetDetailsAsync("1000000001", "Маленький принц", CancellationToken.None);

        details.Should().NotBeNull();
        details!.Type.Should().Be(MediaType.Book);
        details.Type.Should().Be("book");
        details.Title.Should().Be("Маленький принц");
        details.Author.Should().Be("Антуан де Сент-Экзюпери");
    }

    [Theory]
    [InlineData("978-5-353-07328-4", "9785353073284")]
    [InlineData("978 5 353 07328 4", "9785353073284")]
    [InlineData("isbn: 978-5-353-07328-4", "9785353073284")]
    [InlineData("0-306-40615-2", "0306406152")]
    public async Task SearchAsync_WithIsbn_CleansSeparatorsInRequestUrl(string input, string expectedClean)
    {
        string? capturedUrl = null;
        var factory = new StubHttpClientFactory(req =>
        {
            capturedUrl = req.RequestUri?.ToString();
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(SampleSearchHtml)
            };
            return Task.FromResult(response);
        });

        var provider = new LiveLibMetadataProvider(factory);
        await provider.SearchAsync(input, CancellationToken.None);

        capturedUrl.Should().Be($"https://www.livelib.ru/find/books/{expectedClean}");
    }

    [Theory]
    [InlineData("978-5-353-07328-4", true, "9785353073284")]
    [InlineData("9785353073284", true, "9785353073284")]
    [InlineData("isbn: 978-5-353-07328-4", true, "9785353073284")]
    [InlineData("0-8044-2957-X", true, "080442957X")]
    [InlineData("Маленький принц", false, "")]
    [InlineData("https://example.com", false, "")]
    [InlineData("12345", false, "")]
    public void IsIsbnQuery_DetectsValidIsbnStrings(string query, bool expectedValid, string expectedClean)
    {
        var isValid = SearchExternalHandler.IsIsbnQuery(query, out var clean);
        isValid.Should().Be(expectedValid);
        if (expectedValid)
        {
            clean.Should().Be(expectedClean);
        }
    }
}
