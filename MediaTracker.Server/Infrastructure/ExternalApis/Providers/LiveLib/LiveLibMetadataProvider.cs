using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.RegularExpressions;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.External.SearchExternal;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.LiveLib;

/// <summary>
/// The first site scraper in the source registry: LiveLib serves its catalog only as HTML, so this
/// provider reads the search page and the book page directly instead of calling a documented API .
/// Parsing is content-anchored — JSON-LD, OpenGraph, URL
/// shapes and visible text labels — and lives in <see cref="LiveLibHtmlParser"/>, so a stylesheet
/// change on the site cannot silently break it.
/// </summary>
public sealed partial class LiveLibMetadataProvider(
    IHttpClientFactory httpClientFactory,
    ILogger<LiveLibMetadataProvider>? logger = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "livelib",
        Name: "LiveLib",
        Description: "Russian book catalog & community ratings — site scraper (no public API)",
        MediaTypes: ["book"],
        BaseAddress: "https://www.livelib.ru/",
        Priority: 5,
        IsScraper: true,
        // LiveLib answers a bare .NET HttpClient with 403; the browser-shaped UA plus the request
        // headers below pass cleanly.
        UserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36");

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var clean = query.Trim();
        if (clean.Length == 0) return [];

        var isbnCandidate = IsbnCandidateOf(clean);
        if (IsIsbn(isbnCandidate))
        {
            clean = isbnCandidate;
        }

        var client = httpClientFactory.CreateClient(Id);
        var url = $"https://www.livelib.ru/find/books/{Uri.EscapeDataString(clean)}";

        try
        {
            ExternalApiLog.Querying(logger, Name, "book", clean);
            var sw = Stopwatch.StartNew();

            var html = await FetchHtmlAsync(client, url, ct);
            if (html is null)
            {
                ExternalApiLog.Returned(logger, Name, 0, sw.ElapsedMilliseconds);
                return [];
            }

            var items = LiveLibHtmlParser.ParseSearchResults(html)
                .Select(item => new ExternalMediaDto
                {
                    ExternalId = item.Id,
                    ExternalSource = "LiveLib",
                    Title = item.Title,
                    Author = item.Author,
                    CoverUrl = item.CoverUrl,
                    Rating = item.Rating is { } searchRating && searchRating > 0
                        ? Math.Round(searchRating * 2.0, 1)
                        : null,
                    Ratings = item.Rating is { } searchRating2 && searchRating2 > 0
                        ? [new ExternalRatingDto
                        {
                            Source = "LiveLib",
                            Rating = Math.Round(searchRating2 * 2.0, 1),
                        }]
                        : null,
                    Type = MediaType.Book,
                })
                .ToList();

            ExternalApiLog.Returned(logger, Name, items.Count, sw.ElapsedMilliseconds);
            return items;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, url);
            return [];
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var isExternalIdIsbn = !string.IsNullOrWhiteSpace(externalId) && IsIsbn(IsbnCandidateOf(externalId));
        var bookId = isExternalIdIsbn ? null : (BookIdOf(externalId) ?? BookIdOf(title));
        if (bookId is null)
        {
            // Not a LiveLib id: resolve through the search so an ISBN or title-only lookup still works.
            var target = isExternalIdIsbn ? externalId : title;
            var search = string.IsNullOrWhiteSpace(target) ? [] : await SearchAsync(target, ct);
            return search.Count > 0 ? search[0] with { Type = MediaType.Book } : null;
        }

        var client = httpClientFactory.CreateClient(Id);
        var url = $"https://www.livelib.ru/book/{bookId}";

        try
        {
            ExternalApiLog.Querying(logger, Name, "book", bookId);
            var sw = Stopwatch.StartNew();

            var html = await FetchHtmlAsync(client, url, ct);
            if (html is null)
            {
                ExternalApiLog.Failed(logger, Name, System.Net.HttpStatusCode.NotFound, url);
                return null;
            }

            var details = LiveLibHtmlParser.ParseBookPage(html);
            if (string.IsNullOrWhiteSpace(details.Title))
            {
                // A captcha or a stripped page: an empty card would be worse than an honest null.
                logger?.LogWarning("[LiveLib] Book page '{BookId}' parsed to no title", bookId);
                return null;
            }

            ExternalApiLog.Returned(logger, Name, 1, sw.ElapsedMilliseconds);
            return MapDetails(bookId, details);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, url);
            return null;
        }
    }

    /// <summary>
    /// A cheap homepage probe with the same browser headers the scraper needs — a 200 means the
    /// site answers this client shape at all, which is the whole question for a scraper.
    /// </summary>
    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(6));
            using var request = CreateRequest("https://www.livelib.ru/", withReferer: false);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeoutCts.Token);
            sw.Stop();

            if (response.IsSuccessStatusCode)
            {
                ExternalApiLog.Returned(logger, Name, 1, sw.ElapsedMilliseconds);
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            ExternalApiLog.Failed(logger, Name, response.StatusCode, "https://www.livelib.ru/");
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                $"LiveLib ответил {(int)response.StatusCode} {response.ReasonPhrase}");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                "Таймаут соединения с LiveLib (сервис не отвечает)");
        }
        catch (Exception ex)
        {
            sw.Stop();
            ExternalApiLog.Failed(logger, Name, ex, "https://www.livelib.ru/");
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, $"Ошибка сети: {ex.Message}");
        }
    }

    private static ExternalMediaDto MapDetails(string bookId, LiveLibBookDetails details)
    {
        // LiveLib rates on 0–5 stars; the library's external rating lives on the 0–10 scale the
        // other providers map into (OpenLibrary does the same ×2).
        double? rating = details.Rating is { } rawRating && rawRating > 0
            ? Math.Round(rawRating * 2.0, 1)
            : null;

        return new ExternalMediaDto
        {
            ExternalId = bookId,
            ExternalSource = "LiveLib",
            Title = details.Title ?? "Unknown Book",
            Author = details.Author,
            CoverUrl = details.CoverUrl,
            // og:description carries a leading "- " dash on LiveLib pages; strip it once here.
            Description = details.Description?.TrimStart('-', ' '),
            ReleaseYear = details.Year,
            Type = MediaType.Book,
            TotalCount = details.Pages,
            Rating = rating,
            RatingVotes = null,
            Ratings = rating is not null
                ? [new ExternalRatingDto { Source = "LiveLib", Rating = rating.Value }]
                : null,
            Genres = GenreNormalizer.NormalizeList(details.Genres) is { Count: > 0 } genres
                ? genres.Distinct(StringComparer.OrdinalIgnoreCase).Take(8).ToList()
                : null,
        };
    }

    /// <summary>ISBN-10 (digits + optional check X) or ISBN-13 (13 digits), separators already stripped.</summary>
    internal static bool IsIsbn(string value) =>
        Regex.IsMatch(value, """^(?:\d{9}[\dxX]|\d{13})$""");

    /// <summary>The query with hyphens, spaces and an optional "isbn:" prefix stripped away.</summary>
    internal static string IsbnCandidateOf(string query)
    {
        var cleaned = Regex.Replace(query.Trim(), @"[\s\-]", "");
        return cleaned.StartsWith("isbn:", StringComparison.OrdinalIgnoreCase) ? cleaned[5..] : cleaned;
    }

    /// <summary>
    /// The numeric LiveLib id out of a bare id, a slug ("<c>1000804266-master-i-margarita</c>") or a
    /// full URL. A slug-only string (no digits) is not an id and answers null.
    /// </summary>
    internal static string? BookIdOf(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var match = BookIdRegex().Match(value);
        return match.Success ? match.Groups[1].Value : null;
    }

    private async Task<string?> FetchHtmlAsync(System.Net.Http.HttpClient client, string url, CancellationToken ct)
    {
        try
        {
            using var request = CreateRequest(url, withReferer: true);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
            {
                ExternalApiLog.Failed(logger, Name, response.StatusCode, url);
                return null;
            }

            var html = await response.Content.ReadAsStringAsync(ct);
            // A rate-limit or anti-bot interstitial renders as an HTML challenge with no results;
            // parsing it would only ever produce nothing, so it is treated as an empty answer.
            return IsCaptchaPage(html) ? null : html;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, url);
            return null;
        }
    }

    /// <summary>The browser-shaped request LiveLib accepts: browser UA comes from the descriptor's
    /// named client, the accept/language/referer set rides every request.</summary>
    private static System.Net.Http.HttpRequestMessage CreateRequest(string url, bool withReferer)
    {
        var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, url);
        // LiveLib's anti-bot answers HTTP/1.1 book-page requests with 403 (curl and browsers ride
        // HTTP/2 and pass), so every request pins HTTP/2 exactly — the search endpoint tolerates
        // either, but one shape everywhere is simpler to reason about.
        request.Version = HttpVersion.Version20;
        request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
        request.Headers.TryAddWithoutValidation("Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
        request.Headers.TryAddWithoutValidation("Accept-Language", "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7");
        if (withReferer)
        {
            request.Headers.TryAddWithoutValidation("Referer", "https://www.livelib.ru/");
        }

        return request;
    }

    private static bool IsCaptchaPage(string html) =>
        html.Contains("Доступ ограничен", StringComparison.OrdinalIgnoreCase)
        || html.Contains("Подтвердите, что запросы отправляли вы", StringComparison.OrdinalIgnoreCase)
        || (html.Contains("captcha", StringComparison.OrdinalIgnoreCase)
            && html.Contains("yandex", StringComparison.OrdinalIgnoreCase));
    [GeneratedRegex("""(\d{6,12})""")]
    private static partial Regex BookIdRegex();
}
