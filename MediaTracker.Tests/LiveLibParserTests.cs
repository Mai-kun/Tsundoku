using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis.Providers.LiveLib;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Parsing fixtures for the LiveLib scraper: a search-result card and a book page shaped like the
/// real ones (hashed CSS-module classes, HTML comments inside labels, OpenGraph metadata, the
/// JSON-LD block that some pages carry). All anchors are content-based, so these tests double as
/// the regression net for a site-side restyle.
/// </summary>
public class LiveLibParserTests
{
    private const string SearchHtml = """
        <div id="objects-block" class="objects-wrapper">
        <div class="object-wrapper object-edition ll-redirect" data-link="/book/1018128325-master-i-margarita-mihail-bulgakov">
          <a href="/book/1018128325-master-i-margarita-mihail-bulgakov" title="Мастер и Маргарита">
            <span class="object-cover" style="background:url(https://s1.livelib.ru/boocover/1018128325/140x220/b6e7/boocover.jpg) no-repeat;"></span>
          </a>
          <div class="object-info">
            <div class="brow-title"><a href="/book/1018128325-master-i-margarita-mihail-bulgakov" class="title">Мастер и Маргарита</a></div>
            <span class="book-author-item-408"><a class="description " href="/author/408-mihail-bulgakov">Михаил Булгаков</a>, </span>
            <div class="brow-genres"><a class="label-genre" href="/genre/Мистика">Мистика</a></div>
            <span class="rating-book marg-right"><span style="margin-right: 5px" class="rating-value stars-color-gray" itemprop="ratingValue">4,05</span></span>
          </div>
        </div>
        <div class="object-wrapper object-edition ll-redirect" data-link="/book/1002919927-belaya-gvardiya-master-i-margarita-mihail-bulgakov">
          <a href="/book/1002919927-belaya-gvardiya" title="Белая гвардия">
            <span class="object-cover" style="background:url(//s2.livelib.ru/boocover/1002919927/140x220/aaaa/cover.jpg) no-repeat;"></span>
          </a>
          <div class="object-info">
            <div class="brow-title"><a href="/book/1002919927-belaya-gvardiya" class="title">Белая гвардия</a></div>
            <span class="book-author-item-408"><a class="description " href="/author/408-mihail-bulgakov">Михаил Булгаков</a>, </span>
          </div>
        </div>
        </div>
        """;

    private const string BookPageHtml = """
        <html><head>
        <meta property="og:title" content="«Мастер и Маргарита». Автор: Михаил Булгаков">
        <meta property="og:description" content="- Проживите великую историю любви Мастера и Маргариты.">
        <meta property="og:image" content="https://www.livelib.ru/book/1018128325/opengraph-image">
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Book","name":"Мастер и Маргарита","author":[{"@type":"Person","name":"Михаил Булгаков"}],"isbn":"978-5-0063-0439-0","numberOfPages":528,"datePublished":"2026-01-01","image":"https://s1.livelib.ru/boocover/1018128325/200x305/86ee/cover.jpg","aggregateRating":{"@type":"AggregateRating","ratingValue":4.5,"ratingCount":1234}}
        </script>
        </head><body>
        <div class="DetailedInfo_DetailedInfoRow__XXovq"><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">ISBN<!-- -->: </p><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">978-5-0063-0439-0</p></div>
        <div class="DetailedInfo_DetailedInfoRow__XXovq"><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">Год издания<!-- -->: </p><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">1967</p></div>
        <div class="DetailedInfo_DetailedInfoRow__XXovq"><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">Кол-во страниц:	528</p></div>
        <div class="RatingStars_RatingStars__NVTCT" role="radiogroup" aria-label="Рейтинг: 4.5 из 5 звезд" tabindex="-1"></div>
        <a href="/genre/Мистика">Мистика</a>
        <a href="/genre/Русская-классика">Русская классика</a>
        </body></html>
        """;

    private const string BookPageWithoutJsonLd = """
        <html><head>
        <title>Книга — LiveLib</title>
        <meta property="og:title" content="«Белая гвардия». Автор: Михаил Булгаков">
        <meta property="og:description" content="Роман о судьбах белой гвардии.">
        <meta name="description" content="Белая гвардия, Михаил Булгаков.">
        </head><body>
        <div class="DetailedInfo_DetailedInfoRow__XXovq"><p class="DetailedInfo_DetailedInfoRowValue__CFIWF">Кол-во страниц:	352</p></div>
        <div class="RatingStars_RatingStars__NVTCT" role="radiogroup" aria-label="Рейтинг: 4.11 из 5 звезд" tabindex="-1"></div>
        <a href="/genre/Русская-классика\">Русская классика</a>
        </body></html>
        """;

    [Fact]
    public void ParseSearchResults_ExtractsIdTitleAuthorCoverAndRating()
    {
        var items = LiveLibHtmlParser.ParseSearchResults(SearchHtml);

        items.Should().HaveCount(2);
        items[0].Id.Should().Be("1018128325");
        items[0].Title.Should().Be("Мастер и Маргарита");
        items[0].Author.Should().Be("Михаил Булгаков");
        items[0].CoverUrl.Should().Be("https://s1.livelib.ru/boocover/1018128325/140x220/b6e7/boocover.jpg");
        items[0].Rating.Should().BeApproximately(4.05, 0.001);
    }

    [Fact]
    public void ParseSearchResults_NormalizesProtocolRelativeCovers()
    {
        var items = LiveLibHtmlParser.ParseSearchResults(SearchHtml);

        items[1].CoverUrl.Should().StartWith("https://s2.livelib.ru/boocover/");
    }

    [Fact]
    public void ParseSearchResults_DeduplicatesRepeatedCards()
    {
        var doubled = SearchHtml + SearchHtml;
        LiveLibHtmlParser.ParseSearchResults(doubled).Should().HaveCount(2);
    }

    [Fact]
    public void ParseSearchResults_ReturnsEmptyForGarbage()
    {
        LiveLibHtmlParser.ParseSearchResults("").Should().BeEmpty();
        LiveLibHtmlParser.ParseSearchResults("<html><body>Доступ ограничен</body></html>").Should().BeEmpty();
    }

    [Fact]
    public void ParseBookPage_JsonLdAnswersEveryField()
    {
        var details = LiveLibHtmlParser.ParseBookPage(BookPageHtml);

        details.Title.Should().Be("Мастер и Маргарита");
        details.Author.Should().Be("Михаил Булгаков");
        details.Isbn.Should().Be("978-5-0063-0439-0");
        details.Pages.Should().Be(528);
        details.Year.Should().Be(2026); // datePublished wins over the 1967 edition year
        details.Rating.Should().BeApproximately(4.5, 0.001);
        details.CoverUrl.Should().Be("https://s1.livelib.ru/boocover/1018128325/200x305/86ee/cover.jpg");
        details.Genres.Should().Contain("Мистика").And.Contain("Русская классика");
    }

    [Fact]
    public void ParseBookPage_OpenGraphFillsWhenJsonLdMissing()
    {
        var details = LiveLibHtmlParser.ParseBookPage(BookPageWithoutJsonLd);

        details.Title.Should().Be("Белая гвардия");
        details.Author.Should().Be("Михаил Булгаков");
        details.Description.Should().Be("Роман о судьбах белой гвардии.");
        details.Pages.Should().Be(352);
        details.Rating.Should().BeApproximately(4.11, 0.001);
        details.Genres.Should().Contain("Русская классика");
    }

    [Fact]
    public void ParseBookPage_HandlesEmptyAndCaptchaHtml()
    {
        var empty = LiveLibHtmlParser.ParseBookPage("");
        empty.Title.Should().BeNull();

        var captcha = LiveLibHtmlParser.ParseBookPage("<html><body>Доступ ограничен. Подтвердите, что запросы отправляли вы.</body></html>");
        captcha.Title.Should().BeNull();
    }

    [Theory]
    [InlineData("1018128325", "1018128325")]
    [InlineData("1018128325-master-i-margarita", "1018128325")]
    [InlineData("https://www.livelib.ru/book/1018128325-master-i-margarita", "1018128325")]
    [InlineData("/book/1000485837", "1000485837")]
    [InlineData("мастер и маргарита", null)]
    [InlineData("", null)]
    public void BookIdOf_ExtractsTheNumericId(string input, string? expected)
    {
        LiveLibMetadataProvider.BookIdOf(input).Should().Be(expected);
    }
}
