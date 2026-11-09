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
}
