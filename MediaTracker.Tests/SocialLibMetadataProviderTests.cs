using System.Net;
using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis;
using Microsoft.Extensions.Options;
using Xunit;

namespace MediaTracker.Tests;

public class SocialLibMetadataProviderTests
{
    private sealed class StubHttpClientFactory(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name)
        {
            var delegatingHandler = new StubHttpMessageHandler(handler);
            return new HttpClient(delegatingHandler)
            {
                BaseAddress = new Uri("https://api.cdnlibs.org/api/")
            };
        }
    }

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            handler(request);
    }

    [Fact]
    public void SourceDescriptor_ShouldHaveExpectedProperties()
    {
        var descriptor = SocialLibMetadataProvider.Source;
        descriptor.Id.Should().Be("sociallib");
        descriptor.Name.Should().Be("SocialLib (MangaLib / RanobeLib / AnimeLib)");
        descriptor.MediaTypes.Should().BeEquivalentTo(["manga", "book", "anime"]);
        descriptor.RequiresApiKey.Should().BeFalse();
        descriptor.OptionalApiKey.Should().BeTrue();
        descriptor.Aliases.Should().BeEquivalentTo(["mangalib", "ranobelib", "animelib", "slashlib", "hentailib"]);
        descriptor.BaseAddress.Should().Be("https://api.cdnlibs.org/api/");
    }

    [Theory]
    [InlineData("manga", "1", "https://mangalib.me/", "https://mangalib.me")]
    [InlineData("book", "3", "https://ranobelib.me/", "https://ranobelib.me")]
    [InlineData("anime", "5", "https://v5.animelib.org/", "https://v5.animelib.org")]
    public async Task SearchAsync_ShouldSendCorrectHeadersForMediaType(string serviceKey, string expectedSiteId, string expectedReferer, string expectedOrigin)
    {
        HttpRequestMessage? capturedRequest = null;
        var factory = new StubHttpClientFactory(req =>
        {
            capturedRequest = req;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"data":[]}""")
            });
        });

        var options = Options.Create(new ExternalApiOptions());
        var provider = new SocialLibMetadataProvider(factory, options, serviceKey);

        await provider.SearchAsync("test title", CancellationToken.None);

        capturedRequest.Should().NotBeNull();
        capturedRequest!.Headers.GetValues("Site-Id").Should().Contain(expectedSiteId);
        capturedRequest.Headers.GetValues("Referer").Should().Contain(expectedReferer);
        capturedRequest.Headers.GetValues("Origin").Should().Contain(expectedOrigin);
        capturedRequest.Headers.GetValues("Accept").Should().Contain("application/json");
        capturedRequest.Headers.UserAgent.ToString().Should().Contain("Mozilla/5.0");
        capturedRequest.Headers.Authorization.Should().BeNull();
    }

    [Fact]
    public async Task SearchAsync_WithSavedToken_ShouldIncludeBearerHeader()
    {
        HttpRequestMessage? capturedRequest = null;
        var factory = new StubHttpClientFactory(req =>
        {
            capturedRequest = req;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"data":[]}""")
            });
        });

        var apiOptions = new ExternalApiOptions();
        apiOptions.SetKey("sociallib", "my-secret-jwt-token");
        var options = Options.Create(apiOptions);
        var provider = new SocialLibMetadataProvider(factory, options, "manga");

        await provider.SearchAsync("test", CancellationToken.None);

        capturedRequest.Should().NotBeNull();
        capturedRequest!.Headers.Authorization.Should().NotBeNull();
        capturedRequest.Headers.Authorization!.Scheme.Should().Be("Bearer");
        capturedRequest.Headers.Authorization.Parameter.Should().Be("my-secret-jwt-token");
    }

    [Fact]
    public async Task SearchAsync_WhenPrimaryReturns403_ShouldFallbackToSecondaryHost()
    {
        var requestedUris = new List<Uri>();
        var factory = new StubHttpClientFactory(req =>
        {
            requestedUris.Add(req.RequestUri!);
            if (req.RequestUri!.Host == "api.cdnlibs.org")
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""
                {
                    "data": [
                        {
                            "id": 1234,
                            "slug_url": "1234-test-title",
                            "name": "Test Title",
                            "rus_name": "Тестовый заголовок",
                            "site_id": 1,
                            "chap_count": 42,
                            "rate": { "value": 8.5, "votes": 100 }
                        }
                    ]
                }
                """)
            });
        });

        var options = Options.Create(new ExternalApiOptions());
        var provider = new SocialLibMetadataProvider(factory, options, "manga");

        var results = await provider.SearchAsync("test", CancellationToken.None);

        requestedUris.Should().HaveCount(2);
        requestedUris[0].Host.Should().Be("api.cdnlibs.org");
        requestedUris[1].Host.Should().Be("api.lib.social");

        results.Should().HaveCount(1);
        results[0].ExternalId.Should().Be("1234-test-title");
        results[0].Title.Should().Be("Тестовый заголовок");
        results[0].Type.Should().Be("manga");
        results[0].ExternalSource.Should().Be("MangaLib");
        results[0].TotalCount.Should().Be(42);
        results[0].Chapters.Should().Be(42);
        results[0].Rating.Should().Be(8.5);
    }

    [Theory]
    [InlineData(1, "manga", "MangaLib", null)]
    [InlineData(2, "manga", "SlashLib", null)]
    [InlineData(3, "book", "RanobeLib", "light_novel")]
    [InlineData(5, "anime", "AnimeLib", null)]
    public async Task SearchAsync_ShouldMapSiteIdCorrectly(int siteId, string expectedType, string expectedSource, string? expectedMangaFormat)
    {
        var factory = new StubHttpClientFactory(req => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent($$"""
            {
                "data": [
                    {
                        "id": 100,
                        "slug_url": "item-100",
                        "rus_name": "Item 100",
                        "site_id": {{siteId}},
                        "chap_count": 10
                    }
                ]
            }
            """)
        }));

        var options = Options.Create(new ExternalApiOptions());
        var provider = new SocialLibMetadataProvider(factory, options);

        var results = await provider.SearchAsync("item", CancellationToken.None);

        results.Should().HaveCount(1);
        var item = results[0];
        item.Type.Should().Be(expectedType);
        item.ExternalSource.Should().Be(expectedSource);
        item.MangaFormat.Should().Be(expectedMangaFormat);
    }

    [Fact]
    public async Task GetDetailsAsync_ShouldReturnMappedDto()
    {
        var factory = new StubHttpClientFactory(req =>
        {
            req.RequestUri!.ToString().Should().Contain("manga/test-slug");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""
                {
                    "data": {
                        "id": 999,
                        "slug_url": "test-slug",
                        "name": "Novel Slug",
                        "rus_name": "Тестовое ранобэ",
                        "site_id": 3,
                        "chap_count": 150,
                        "summary": "Описание ранобэ",
                        "rate": { "avg": "9.2", "votes": 50 }
                    }
                }
                """)
            });
        });

        var options = Options.Create(new ExternalApiOptions());
        var provider = new SocialLibMetadataProvider(factory, options, "book");

        var details = await provider.GetDetailsAsync("test-slug", "Тестовое ранобэ", CancellationToken.None);

        details.Should().NotBeNull();
        details!.ExternalId.Should().Be("test-slug");
        details.Title.Should().Be("Тестовое ранобэ");
        details.Type.Should().Be("book");
        details.MangaFormat.Should().Be("light_novel");
        details.ExternalSource.Should().Be("RanobeLib");
        details.Description.Should().Be("Описание ранобэ");
        details.Rating.Should().Be(9.2);
        details.RatingVotes.Should().Be(50);
        details.Ratings.Should().ContainSingle(r => r.Source == "RanobeLib" && r.Rating == 9.2);
    }
}
