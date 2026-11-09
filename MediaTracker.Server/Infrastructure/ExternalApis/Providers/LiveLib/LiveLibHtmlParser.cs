using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.LiveLib;

/// <summary>One row of the LiveLib search page.</summary>
public sealed record LiveLibSearchItem(
    string Id,
    string Title,
    string? Author,
    string? CoverUrl,
    double? Rating);

/// <summary>
/// Everything the book page yields. Fields stay nullable: the page cascade fills what it can, and
/// the provider decides the DTO mapping.
/// </summary>
public sealed record LiveLibBookDetails(
    string? Title,
    string? Author,
    string? Description,
    string? Isbn,
    int? Pages,
    int? Year,
    double? Rating,
    string? CoverUrl,
    IReadOnlyList<string> Genres);

/// <summary>
/// Extracts LiveLib data from raw HTML with content-anchored matching only: URL shapes
/// (<c>/book/{id}</c>, <c>/genre/…</c>, <c>s*.livelib.ru/boocover/…</c>), JSON-LD, OpenGraph meta
/// and visible text labels ("Кол-во страниц:"). LiveLib styles its pages with hashed CSS-module
/// class names, so nothing here may key off a class name — a stylesheet change must not break this.
/// </summary>
public static partial class LiveLibHtmlParser
{
    /// <summary>Parse a find/books answer into its result rows (up to the caller's limit).</summary>
    public static IReadOnlyList<LiveLibSearchItem> ParseSearchResults(string html)
    {
        var items = new List<LiveLibSearchItem>();
        if (string.IsNullOrWhiteSpace(html))
        {
            return items;
        }

        var matches = BookLinkRegex().Matches(html);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var block in SplitBlocks(html, matches))
        {
            var id = block.Id;
            if (!seen.Add(id)) continue;

            var title = ExtractTitle(block.Html) ?? string.Empty;
            if (title.Length == 0) continue;

            items.Add(new LiveLibSearchItem(
                Id: id,
                Title: DecodeHtml(title),
                Author: ExtractAuthors(block.Html),
                CoverUrl: ExtractBoocover(block.Html),
                Rating: ExtractRatingValue(block.Html)));
            if (items.Count >= 15) break;
        }

        return items;
    }

    /// <summary>
    /// The three-level cascade for a book page. JSON-LD wins where present, OpenGraph/meta fills
    /// the gaps, and the page's own text labels (ISBN, page count, publication year, genres) finish
    /// the rest. Each field independently falls through the levels, so a JSON-LD block without a
    /// description still leaves the OpenGraph one to answer.
    /// </summary>
    public static LiveLibBookDetails ParseBookPage(string html)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            return new LiveLibBookDetails(null, null, null, null, null, null, null, null, []);
        }

        // Level 1: schema.org JSON-LD (type "Book"). Absent on most current pages, but it is the
        // most stable contract the site can grow into, so it leads the cascade.
        string? title = null, author = null, description = null, isbn = null, cover = null;
        int? pages = null;
        int? year = null;
        double? rating = null;

        foreach (var json in JsonLdBlocks(html))
        {
            using var document = SafeParse(json);
            if (document is null) continue;
            foreach (var element in EnumerateBookNodes(document.RootElement))
            {
                title ??= StringProperty(element, "name");
                author ??= StringProperty(element, "author");
                description ??= StringProperty(element, "description");
                isbn ??= StringProperty(element, "isbn");

                if (pages is null && element.TryGetProperty("numberOfPages", out var pagesEl)
                    && pagesEl.ValueKind == JsonValueKind.Number)
                {
                    pages = pagesEl.GetInt32();
                }

                if (year is null)
                {
                    var published = StringProperty(element, "datePublished");
                    if (published is { Length: >= 4 } raw && int.TryParse(raw[..4], out var parsedYear))
                    {
                        year = parsedYear;
                    }
                }

                cover ??= StringProperty(element, "image");

                if (rating is null && element.TryGetProperty("aggregateRating", out var agg)
                    && agg.ValueKind == JsonValueKind.Object
                    && agg.TryGetProperty("ratingValue", out var ratingEl))
                {
                    rating = ratingEl.ValueKind switch
                    {
                        JsonValueKind.Number => ratingEl.GetDouble(),
                        JsonValueKind.String when double.TryParse(
                            ratingEl.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) => parsed,
                        _ => null,
                    };
                }
            }
        }

        // Level 2: OpenGraph and meta description. og:title carries both the title and the author
        // in one string: «Мастер и Маргарита». Автор: Михаил Булгаков.
        var ogTitle = MetaContent(html, "property", "og:title");
        if (title is null && ogTitle is not null)
        {
            var quoted = QuotedTitleRegex().Match(ogTitle);
            title = quoted.Success ? quoted.Groups[1].Value.Trim() : ogTitle.Trim();
        }

        if (author is null && ogTitle is not null)
        {
            var authorMatch = OgAuthorRegex().Match(ogTitle);
            if (authorMatch.Success)
            {
                author = authorMatch.Groups[1].Value.Trim();
            }
        }

        description ??= MetaContent(html, "property", "og:description")
            ?? MetaContent(html, "name", "description");

        // The boocover asset beats the opengraph renderer: it is the real cover file with its
        // original name, and it is what the search rows carry too.
        var boocover = ExtractBoocover(html);
        cover = NormalizeCover(boocover ?? cover);
        cover ??= MetaContent(html, "property", "og:image");

        // Level 3: page text labels and the genre block.
        isbn ??= IsbnRegex().Match(html) is { Success: true } isbnMatch
            ? isbnMatch.Groups[1].Value.TrimEnd('-')
            : null;
        pages ??= NonNegative(PagesRegex().Match(html) is { Success: true } pagesMatch
            ? pagesMatch.Groups[1].Value
            : null);
        year ??= NonNegative(YearRegex().Match(html) is { Success: true } yearMatch
            ? yearMatch.Groups[1].Value
            : null);
        rating ??= ExtractRatingValue(html);

        // The link's visible text ("Русская классика") beats the slug ("Русская-классика"); the
        // slug is the fallback for genre links that render no text.
        var genres = GenreRegex().Matches(html)
            .Select(m =>
            {
                var label = m.Groups[2].Success && m.Groups[2].Value.Trim().Length > 1
                    ? m.Groups[2].Value
                    : (Uri.TryCreate(m.Groups[1].Value, UriKind.Relative, out _)
                        ? Uri.UnescapeDataString(m.Groups[1].Value)
                        : m.Groups[1].Value);
                return DecodeHtml(label).Trim().TrimEnd('\\', '/');
            })
            .Where(g => g.Length > 1)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return new LiveLibBookDetails(
            Title: title is null ? null : DecodeHtml(title),
            Author: author is null ? null : DecodeHtml(author),
            Description: description is null ? null : DecodeHtml(description).Trim(),
            Isbn: isbn,
            Pages: pages,
            Year: year,
            Rating: rating,
            CoverUrl: cover,
            Genres: genres);
    }

    private sealed record HtmlBlock(string Id, string Html);

    /// <summary>
    /// Chunks the page by each <c>data-link="/book/{id}…"</c> marker so the regexes below only see
    /// one result card at a time.
    /// </summary>
    private static IEnumerable<HtmlBlock> SplitBlocks(string html, MatchCollection matches)
    {
        for (var i = 0; i < matches.Count; i++)
        {
            var idMatch = BookIdRegex().Match(matches[i].Groups[1].Value);
            if (!idMatch.Success) continue;

            var start = matches[i].Index;
            var end = i + 1 < matches.Count ? matches[i + 1].Index : Math.Min(html.Length, start + 6000);
            yield return new HtmlBlock(idMatch.Groups[1].Value, html[start..end]);
        }
    }

    private static string? ExtractTitle(string block)
    {
        // The link's text is the clean title; the title attribute prefixes the author
        // ("Михаил Булгаков - Мастер и Маргарита"), so it is only a fallback.
        var plain = TitleLinkRegex().Match(block);
        if (plain.Success) return plain.Groups[1].Value;
        var titled = TitleAttrRegex().Match(block);
        return titled.Success ? titled.Groups[1].Value : null;
    }

    private static string? ExtractAuthors(string block)
    {
        var names = AuthorRegex().Matches(block)
            .Select(m => DecodeHtml(m.Groups[1].Value.Trim()))
            .Where(n => n.Length > 0 && !n.Equals("показать всех", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(4)
            .ToList();
        return names.Count > 0 ? string.Join(", ", names) : null;
    }

    private static string? ExtractBoocover(string block)
    {
        var match = BoocoverRegex().Match(block);
        return match.Success ? NormalizeCover(match.Groups[1].Value) : null;
    }

    private static double? ExtractRatingValue(string html)
    {
        var itemprop = RatingValueRegex().Match(html);
        if (itemprop.Success
            && double.TryParse(itemprop.Groups[1].Value.Replace(',', '.'), NumberStyles.Float,
                CultureInfo.InvariantCulture, out var parsed)
            && parsed > 0)
        {
            return parsed;
        }

        // The stars widget carries the value in an aria-label: "Рейтинг: 4.5 из 5 звезд".
        var aria = RatingAriaRegex().Match(html);
        if (aria.Success
            && double.TryParse(aria.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var ariaParsed)
            && ariaParsed > 0)
        {
            return ariaParsed;
        }

        return null;
    }

    /// <summary>Protocol-relative and bare asset URLs get a scheme; anything else passes through.</summary>
    private static string? NormalizeCover(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        var trimmed = url.Trim();
        if (trimmed.StartsWith("//")) return $"https:{trimmed}";
        return trimmed;
    }

    private static string? MetaContent(string html, string attribute, string key)
    {
        // attribute/content order can flip between renders, so both orders are tried.
        var escapedKey = Regex.Escape(key);
        var match = Regex.Match(
            html,
            "<meta\\s+" + attribute + "=\"" + escapedKey + "\"\\s+content=\"([^\"]*)\"",
            RegexOptions.IgnoreCase);
        if (!match.Success)
        {
            match = Regex.Match(
                html,
                "<meta\\s+content=\"([^\"]*)\"\\s+" + attribute + "=\"" + escapedKey + "\"",
                RegexOptions.IgnoreCase);
        }

        var value = match.Success ? match.Groups[1].Value : null;
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    private static IEnumerable<JsonElement> EnumerateBookNodes(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in root.EnumerateArray())
            {
                foreach (var node in EnumerateBookNodes(item)) yield return node;
            }

            yield break;
        }

        if (root.ValueKind != JsonValueKind.Object) yield break;

        if (root.TryGetProperty("@type", out var type))
        {
            var typeValue = type.ValueKind == JsonValueKind.Array
                ? string.Join(",", type.EnumerateArray().Select(t => t.ToString()))
                : type.ToString();
            if (typeValue.Contains("Book", StringComparison.OrdinalIgnoreCase))
            {
                yield return root;
                yield break;
            }
        }

        if (root.TryGetProperty("@graph", out var graph) && graph.ValueKind == JsonValueKind.Array)
        {
            foreach (var node in EnumerateBookNodes(graph)) yield return node;
        }
    }

    private static string? StringProperty(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;

        return value.ValueKind switch
        {
            JsonValueKind.String => NullIfBlank(value.GetString()),
            JsonValueKind.Array => NullIfBlank(string.Join(", ", value.EnumerateArray()
                .Select(item => item.ValueKind == JsonValueKind.Object
                        ? (item.TryGetProperty("name", out var nameEl) ? nameEl.ToString() : null)
                        : item.ToString())
                .Where(part => !string.IsNullOrWhiteSpace(part)))),
            JsonValueKind.Object => NullIfBlank(
                value.TryGetProperty("name", out var nameEl) ? nameEl.ToString() : null),
            _ => null,
        };
    }

    private static JsonDocument? SafeParse(string json)
    {
        try
        {
            return JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static IEnumerable<string> JsonLdBlocks(string html)
    {
        foreach (var match in JsonLdRegex().Matches(html).Cast<Match>())
        {
            var payload = match.Groups[1].Value.Trim();
            if (payload.Length > 0) yield return payload;
        }
    }

    private static int? NonNegative(string? value) =>
        int.TryParse(value, out var parsed) && parsed > 0 ? parsed : null;

    private static string? NullIfBlank(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>HTML-unescape plus a <c><!-- --></c> comment strip: LiveLib sprinkles empty comments
    /// into its labels ("ISBN<!-- -->: 978-…").</summary>
    private static string DecodeHtml(string value) =>
        System.Net.WebUtility.HtmlDecode(value.Replace("<!-- -->", string.Empty)).Trim();

    // Four-quote raw strings: the patterns themselves contain double quotes.
    [GeneratedRegex(""""data-link="(/book/\d+[^"]*)"""")]
    private static partial Regex BookLinkRegex();

    [GeneratedRegex(@"^/book/(\d+)")]
    private static partial Regex BookIdRegex();

    [GeneratedRegex(""""<a[^>]*href="/book/\d+[^"]*"[^>]*title="([^"]+)"""")]
    private static partial Regex TitleAttrRegex();

    [GeneratedRegex("""<a[^>]*class="[^"]*\btitle\b[^"]*"[^>]*>([^<]+)</a>""")]
    private static partial Regex TitleLinkRegex();

    [GeneratedRegex(""""<a[^>]*href="/author/\d+[^"]*"[^>]*>([^<]+)</a>"""")]
    private static partial Regex AuthorRegex();

    [GeneratedRegex("((?:https?:)?//s\\d+\\.livelib\\.ru/boocover/[^)\"\\s\\\\]+)")]
    private static partial Regex BoocoverRegex();

    [GeneratedRegex("""itemprop="ratingValue">\s*([0-9]+[.,][0-9]+)\s*<""")]
    private static partial Regex RatingValueRegex();

    [GeneratedRegex("""aria-label="Рейтинг:\s*([0-9.]+) из 5""")]
    private static partial Regex RatingAriaRegex();

    [GeneratedRegex("""<script type="application/ld\+json">\s*(\{.*?\})\s*</script>""", RegexOptions.Singleline)]
    private static partial Regex JsonLdRegex();

    [GeneratedRegex("""«(.+?)»""", RegexOptions.Singleline)]
    private static partial Regex QuotedTitleRegex();

    [GeneratedRegex("""Автор:\s*(.+?)\s*$""")]
    private static partial Regex OgAuthorRegex();

    [GeneratedRegex("""ISBN[^0-9\n]{0,24}(97[89][\d\-]{10,16}|\d{9}[\dXx])""")]
    private static partial Regex IsbnRegex();

    [GeneratedRegex("""(?:Кол-во|Число) страниц:\s*(\d{1,4})""")]
    private static partial Regex PagesRegex();

    [GeneratedRegex("""Год издания[^0-9]{0,24}(\d{4})""")]
    private static partial Regex YearRegex();

    [GeneratedRegex(""""<a[^>]*href="/genre/([^"#?]+)"[^>]*>([^<]+)</a>"""")]
    private static partial Regex GenreRegex();
}
