using System.Net;
using FluentAssertions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common.Proxy;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// Контракт динамической маршрутизации внешних запросов через прокси:
/// локальные цели всегда мимо прокси, проксируются только отмеченные источники,
/// смена конфигурации подхватывается на лету (тот же экземпляр прокси, без рестарта).
/// </summary>
public class DynamicSourceProxyTests
{
    private static ProxySettingsSnapshot Snapshot(
        bool enabled,
        string url,
        string[] sources,
        string? username = null,
        string? password = null)
    {
        var (snapshot, error) = ProxySettingsSnapshot.Build(enabled, url, username, password, sources);
        error.Should().BeNull("тестовые настройки прокси должны парситься");
        return snapshot;
    }

    private static ProxySettingsService NewService(ProxySettingsSnapshot snapshot)
    {
        var service = new ProxySettingsService();
        service.Update(snapshot);
        return service;
    }

    [Fact]
    public void GetProxy_SourceListed_RoutesThroughProxy()
    {
        var service = NewService(Snapshot(true, "socks5://127.0.0.1:1080", ["mangadex", "tmdb"]));
        var proxy = new DynamicSourceProxy(service, "mangadex");

        var resolved = proxy.GetProxy(new Uri("https://api.mangadex.org/manga"));

        resolved.Should().Be(new Uri("socks5://127.0.0.1:1080"));
        proxy.IsBypassed(new Uri("https://api.mangadex.org/manga")).Should().BeFalse();
    }

    [Fact]
    public void GetProxy_SourceNotListed_GoesDirect()
    {
        var service = NewService(Snapshot(true, "http://127.0.0.1:2080", ["tmdb"]));
        var proxy = new DynamicSourceProxy(service, "mangadex");

        proxy.GetProxy(new Uri("https://api.mangadex.org/manga")).Should().BeNull();
        proxy.IsBypassed(new Uri("https://api.mangadex.org/manga")).Should().BeTrue();
    }

    [Theory]
    [InlineData("https://localhost:5000/api")]
    [InlineData("http://127.0.0.1:5000/api/media")]
    [InlineData("http://192.168.1.10/shared")]
    [InlineData("http://10.0.0.5/internal")]
    [InlineData("http://172.16.0.1/")]
    [InlineData("http://169.254.169.254/metadata")]
    [InlineData("https://nas.local/")]
    [InlineData("https://router.lan/")]
    public void GetProxy_LocalAndInternalTargets_AreNeverProxied(string target)
    {
        // Прокси включён, источник отмечен — но локальные адреса всё равно мимо прокси.
        var service = NewService(Snapshot(true, "socks5://127.0.0.1:1080", ["mangadex"]));
        var proxy = new DynamicSourceProxy(service, "mangadex");

        proxy.GetProxy(new Uri(target)).Should().BeNull();
        proxy.IsBypassed(new Uri(target)).Should().BeTrue();
    }

    [Fact]
    public void GetProxy_Disabled_GoesDirect_EvenForListedSources()
    {
        var service = NewService(Snapshot(false, "socks5://127.0.0.1:1080", ["mangadex"]));
        var proxy = new DynamicSourceProxy(service, "mangadex");

        proxy.GetProxy(new Uri("https://api.mangadex.org/manga")).Should().BeNull();
    }

    [Fact]
    public void ConfigurationChange_AppliesImmediately_WithoutRestart()
    {
        // Один и тот же экземпляр прокси: клиенты живут в DI, менять должен только снимок.
        var service = new ProxySettingsService();
        var proxy = new DynamicSourceProxy(service, "tmdb");
        var target = new Uri("https://api.themoviedb.org/3/movie/550");

        proxy.GetProxy(target).Should().BeNull("прокси ещё не настроен");

        service.Update(Snapshot(true, "http://proxy.example:3128", ["tmdb"]));
        proxy.GetProxy(target).Should().Be(new Uri("http://proxy.example:3128"), "источник включили в ProxiedSources");

        service.Update(Snapshot(true, "http://proxy.example:3128", []));
        proxy.GetProxy(target).Should().BeNull("источник убрали из ProxiedSources");

        service.Update(Snapshot(false, "http://proxy.example:3128", ["tmdb"]));
        proxy.GetProxy(target).Should().BeNull("мастер-рубильник выключен");
    }

    [Fact]
    public void UnboundClient_ResolvesSourceByHostRoot()
    {
        // Клиенты обложек и импорта не привязаны к источнику — маршрут ищется по домену.
        var service = NewService(Snapshot(true, "http://proxy.example:3128", ["tmdb", "mangadex", "sociallib"]));
        var proxy = new DynamicSourceProxy(service, null);

        proxy.GetProxy(new Uri("https://image.tmdb.org/t/p/w500/poster.jpg")).Should().NotBeNull("image.tmdb.org → tmdb");
        proxy.GetProxy(new Uri("https://uploads.mangadex.org/covers/1/a.webp")).Should().NotBeNull("uploads.mangadex.org → mangadex");
        proxy.GetProxy(new Uri("https://cover.imglib.info/x.jpg")).Should().NotBeNull("cover.imglib.info → sociallib");
        proxy.GetProxy(new Uri("https://unknown-cdn.example/cover.webp")).Should().BeNull("домен не принадлежит ни одному источнику");
    }

    [Fact]
    public void Credentials_ExposeProxyAuthentication_WhenUsernameSet()
    {
        var service = NewService(Snapshot(true, "http://proxy.example:3128", ["tmdb"], "user", "secret"));
        var proxy = new DynamicSourceProxy(service, "tmdb");

        proxy.Credentials.Should().NotBeNull();
        var credential = proxy.Credentials!.GetCredential(new Uri("http://proxy.example:3128"), "basic");
        credential.Should().NotBeNull();
        credential!.UserName.Should().Be("user");
        credential.Password.Should().Be("secret");
    }

    [Fact]
    public void Credentials_AreNull_WhenProxyDisabled()
    {
        var service = NewService(ProxySettingsSnapshot.Disabled);
        var proxy = new DynamicSourceProxy(service, "tmdb");

        proxy.Credentials.Should().BeNull();
    }

    [Fact]
    public void Snapshot_Build_AcceptsAllSupportedSchemes()
    {
        var expected = new (string Url, string Scheme, string Host, int Port)[]
        {
            ("http://127.0.0.1:2080", "http", "127.0.0.1", 2080),
            ("https://proxy.example.com:8443", "https", "proxy.example.com", 8443),
            ("socks5://127.0.0.1:1080", "socks5", "127.0.0.1", 1080),
            ("socks5h://127.0.0.1:1080", "socks5h", "127.0.0.1", 1080),
        };

        foreach (var (url, scheme, host, port) in expected)
        {
            var (snapshot, error) = ProxySettingsSnapshot.Build(true, url, null, null, []);
            error.Should().BeNull(url);
            snapshot.Enabled.Should().BeTrue();
            snapshot.ProxyUri!.Scheme.Should().Be(scheme);
            snapshot.ProxyUri.Host.Should().Be(host);
            snapshot.ProxyUri.Port.Should().Be(port);
        }
    }

    [Fact]
    public void Snapshot_Build_RejectsUnsupportedSchemeAndEmptyUrl()
    {
        var (bad, badError) = ProxySettingsSnapshot.Build(true, "ftp://proxy.example", null, null, []);
        badError.Should().NotBeNull("схема ftp не поддерживается");
        bad.Enabled.Should().BeFalse();

        var (empty, emptyError) = ProxySettingsSnapshot.Build(true, "  ", null, null, []);
        emptyError.Should().NotBeNull("включённый прокси без адреса бессмыслен");
        empty.Enabled.Should().BeFalse();
    }

    [Fact]
    public void Snapshot_Build_IgnoresCaseAndWhitespaceInSources()
    {
        var (snapshot, error) = ProxySettingsSnapshot.Build(true, "http://p:1", null, null, [" MangaDex ", "TMDB"]);
        error.Should().BeNull();

        snapshot.ProxiedSources.Should().HaveCount(2);
        snapshot.ProxiedSources.Contains("mangadex").Should().BeTrue("сравнение без учёта регистра");
        snapshot.ProxiedSources.Contains("tmdb").Should().BeTrue();
    }

    [Fact]
    public void RootDomain_MapsCoverCdnsOntoTheirApiRoots()
    {
        ProxySettingsService.RootDomain("api.mangadex.org").Should().Be("mangadex.org");
        ProxySettingsService.RootDomain("uploads.mangadex.org").Should().Be("mangadex.org");
        // Корни у API и CDN TMDb разные — поэтому image.tmdb.org добавлен в карту явно.
        ProxySettingsService.RootDomain("image.tmdb.org").Should().Be("tmdb.org");
        ProxySettingsService.RootDomain("api.themoviedb.org").Should().Be("themoviedb.org");

        var service = new ProxySettingsService();
        service.ResolveSourceId(new Uri("https://image.tmdb.org/t/p/w500/x.jpg"), null).Should().Be("tmdb");
        service.ResolveSourceId(new Uri("https://api.themoviedb.org/3/movie/550"), null).Should().Be("tmdb");
    }

    [Fact]
    public void ProxyAddressGuard_BlocksLoopbackAndPrivateRanges()
    {
        foreach (var host in new[]
                 {
                     "localhost", "127.0.0.1", "::1", "10.1.2.3", "192.168.0.1",
                     "172.31.255.255", "169.254.10.10", "0.0.0.0", "box.internal", "printer.local",
                 })
        {
            ProxyAddressGuard.IsPublicHost(host).Should().BeFalse(host);
        }

        foreach (var host in new[] { "api.mangadex.org", "image.tmdb.org", "cover.imglib.info", "8.8.8.8" })
        {
            ProxyAddressGuard.IsPublicHost(host).Should().BeTrue(host);
        }
    }
}
