using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

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
    IReadOnlyList<string> Genres)
{
    /// <summary>The edition's publisher, from JSON-LD <c>publisher.name</c> or the page label.</summary>
    public string? Publisher { get; init; }

    /// <summary>Binding as a readable label ("Твёрдый переплёт"), mapped from <c>bookFormat</c>.</summary>
    public string? Format { get; init; }

    /// <summary>Edition language, from JSON-LD <c>inLanguage</c> or the "Язык" row.</summary>
    public string? Language { get; init; }

    /// <summary>Publication date (yyyy-MM-dd) from <c>datePublished</c>; null when the source has none.</summary>
    public string? ReleaseDate { get; init; }

    public int? RatingVotes { get; init; }

    /// <summary>True when the JSON-LD rating is already on a 10-point scale (bestRating 10).</summary>
    public bool RatingIsTenPoint { get; init; }

    /// <summary>The "Серия" row value; the provider exposes it as a tag.</summary>
    public string? Series { get; init; }

    /// <summary>Edition staff the page names, e.g. the illustrator.</summary>
    public IReadOnlyList<ExternalStaffMemberDto>? Staff { get; init; }

    /// <summary>Age restriction string (e.g. "6+").</summary>
    public string? AgeRating { get; init; }

    /// <summary>List of adaptation titles from the overview section.</summary>
    public IReadOnlyList<string>? Adaptations { get; init; }

    /// <summary>Interesting facts overview section text.</summary>
    public string? Facts { get; init; }

    /// <summary>History or creation story overview section text.</summary>
    public string? History { get; init; }
}

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

        // Level 1: schema.org JSON-LD (type "Book"). It may sit at the root or inside an @graph
        // wrapper, and it is the most stable contract the site offers, so it leads the cascade.
        string? title = null, author = null, description = null, isbn = null, cover = null;
        string? publisher = null, format = null, language = null, releaseDate = null;
        int? pages = null;
        int? year = null;
        int? ratingVotes = null;
        double? rating = null;
        var ratingIsTenPoint = false;
        var jsonGenres = new List<string>();

        foreach (var json in JsonLdBlocks(html))
        {
            using var document = SafeParse(json);
            if (document is null) continue;
            foreach (var element in EnumerateBookNodes(document.RootElement))
            {
                title ??= StringProperty(element, "name");
                author ??= StringProperty(element, "author");
                description ??= UsableDescription(StringProperty(element, "description"));
                isbn ??= StringProperty(element, "isbn");
                publisher ??= StringProperty(element, "publisher");
                format ??= FormatOf(StringProperty(element, "bookFormat"));
                language ??= StringProperty(element, "inLanguage");
                cover ??= ImageUrlProperty(element, "image");

                if (pages is null && element.TryGetProperty("numberOfPages", out var pagesEl)
                    && pagesEl.ValueKind == JsonValueKind.Number)
                {
                    pages = pagesEl.GetInt32();
                }

                var published = StringProperty(element, "datePublished");
                if (published is { Length: >= 4 })
                {
                    if (year is null && int.TryParse(published[..4], out var parsedYear))
                    {
                        year = parsedYear;
                    }

                    releaseDate ??= DatePartRegex().Match(published) is { Success: true } dateMatch
                        ? dateMatch.Value
                        : published;
                }

                if (jsonGenres.Count == 0)
                {
                    jsonGenres.AddRange(StringArrayProperty(element, "genre"));
                }

                if (element.TryGetProperty("aggregateRating", out var agg)
                    && agg.ValueKind == JsonValueKind.Object)
                {
                    if (rating is null && TryDoubleProperty(agg, "ratingValue") is { } parsedRating)
                    {
                        rating = parsedRating;
                        var best = TryDoubleProperty(agg, "bestRating");
                        // LiveLib's newer JSON-LD is already 1-10 (bestRating 10); the older
                        // pages used the site's 0-5 stars.
                        ratingIsTenPoint = best >= 10 || parsedRating > 5;
                    }

                    ratingVotes ??= TryIntProperty(agg, "ratingCount");
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

        // The real book annotation on the page beats the templated og/meta blurb
        // ("Книга «…». Автор: …"), which is not a synopsis at all.
        description ??= ExtractAnnotation(html);
        description ??= UsableDescription(MetaContent(html, "property", "og:description"));
        description ??= UsableDescription(MetaContent(html, "name", "description"));
        // If no full synopsis exists on the edition, fall back to cleaned og:description
        // so description is never left null.
        description ??= CleanOgDescription(MetaContent(html, "property", "og:description"));
        description ??= CleanOgDescription(MetaContent(html, "name", "description"));

        var facts = ExtractOverviewSection(html, FactsSectionRegex());
        var history = ExtractOverviewSection(html, HistorySectionRegex());
        var adaptations = ExtractAdaptations(html);

        description = ComposeDescription(description, facts, history);

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
        if (rating is null)
        {
            rating = ExtractRatingValue(html);
        }

        var pagePublisher = CleanPublisher(ExtractLabeledValue(html, "Издательство"));
        if (!string.IsNullOrWhiteSpace(pagePublisher))
        {
            if (string.IsNullOrWhiteSpace(publisher)
                || pagePublisher.Length > publisher.Length
                || pagePublisher.Contains(publisher, StringComparison.OrdinalIgnoreCase))
            {
                publisher = pagePublisher;
            }
        }
        format ??= FormatOf(ExtractLabeledValue(html, "Переплет"));
        language ??= ExtractLabeledValue(html, "Язык");
        var series = ExtractLabeledValue(html, "Серия");
        var ageRating = ExtractAgeRating(html);

        // The link's visible text ("Русская классика") beats the slug ("Русская-классика"); the
        // slug is the fallback for genre links that render no text.
        var pageGenres = GenreRegex().Matches(html)
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
        var genres = jsonGenres.Count > 0
            ? jsonGenres.Distinct(StringComparer.OrdinalIgnoreCase).ToList()
            : pageGenres;

        return new LiveLibBookDetails(
            Title: title is null ? null : DecodeHtml(title),
            Author: author is null ? null : DecodeHtml(author),
            Description: description is null ? null : DecodeHtml(description).Trim(),
            Isbn: isbn,
            Pages: pages,
            Year: year,
            Rating: rating,
            CoverUrl: cover,
            Genres: genres)
        {
            Publisher = publisher,
            Format = format,
            Language = language,
            ReleaseDate = releaseDate,
            RatingVotes = ratingVotes,
            RatingIsTenPoint = ratingIsTenPoint,
            Series = series,
            Staff = ExtractStaff(html),
            AgeRating = ageRating,
            Adaptations = adaptations,
            Facts = facts,
            History = history,
        };
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

    /// <summary>
    /// The JSON-LD/OpenGraph description, unless it is LiveLib's templated blurb
    /// ("Книга «…». Автор: …" / "Предлагаем вашему вниманию книгу …"), which carries no synopsis.
    /// </summary>
    private static string? UsableDescription(string? value)
    {
        var text = value is null ? null : DecodeHtml(value).Trim().TrimStart('-', ' ');
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (TemplateDescriptionRegex().IsMatch(text)) return null;
        return text;
    }

    /// <summary>Fallback cleaned description when no custom annotation exists.</summary>
    private static string? CleanOgDescription(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var text = DecodeHtml(value).Trim().TrimStart('-', ' ');
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }

    /// <summary>
    /// The book annotation from the page. Checks modern LiveLib sections (ShortInfoDescription,
    /// TruncateContent), older layout blocks, and Next.js artDescription.
    /// </summary>
    private static string? ExtractAnnotation(string html)
    {
        foreach (var opening in new[]
                 {
                     ShortInfoDescriptionRegex(),
                     TruncateContentRegex(),
                     ItempropDescriptionRegex(),
                     LentaDescriptionRegex(),
                     CardDescriptionRegex(),
                 })
        {
            var text = HtmlToText(InnerHtmlOf(html, opening));
            if (text is { Length: >= 20 }) return text;
        }

        var artMatch = ArtDescriptionRegex().Match(html);
        if (artMatch.Success)
        {
            var raw = artMatch.Groups[1].Value;
            var unescaped = Regex.Unescape(raw);
            var text = HtmlToText(unescaped);
            if (text is { Length: >= 20 }) return text;
        }

        return null;
    }

    private static string? ExtractOverviewSection(string html, Regex sectionRegex)
    {
        var match = sectionRegex.Match(html);
        if (!match.Success) return null;

        var raw = HtmlButtonRegex().Replace(match.Groups[1].Value, string.Empty);
        return HtmlToText(raw);
    }

    private static IReadOnlyList<string>? ExtractAdaptations(string html)
    {
        var section = ExtractOverviewSection(html, AdaptationsSectionRegex());
        if (string.IsNullOrWhiteSpace(section)) return null;

        var items = section.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(line => line.Length > 0 && !line.Equals("Ещё", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return items.Count > 0 ? items : null;
    }

    private static string? FormatFacts(string rawFacts)
    {
        if (string.IsNullOrWhiteSpace(rawFacts)) return null;
        var lines = rawFacts.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var formatted = new List<string>();
        foreach (var line in lines)
        {
            if (AttributionRegex().IsMatch(line)) continue;
            if (line.Equals("Ещё", StringComparison.OrdinalIgnoreCase)) continue;
            var cleaned = BulletPrefixRegex().Replace(line, string.Empty).Trim();
            if (cleaned.Length > 0)
            {
                formatted.Add($"• {cleaned}");
            }
        }

        return formatted.Count > 0 ? string.Join("\n", formatted) : null;
    }

    private static string? CleanHistory(string rawHistory)
    {
        if (string.IsNullOrWhiteSpace(rawHistory)) return null;
        var lines = rawHistory.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(line => !line.Equals("Ещё", StringComparison.OrdinalIgnoreCase) && !AttributionRegex().IsMatch(line));
        var cleaned = string.Join("\n", lines).Trim();
        return cleaned.Length > 0 ? cleaned : null;
    }

    private static string? ComposeDescription(string? baseDescription, string? facts, string? history)
    {
        var parts = new List<string>();

        if (!string.IsNullOrWhiteSpace(baseDescription))
        {
            parts.Add(baseDescription.Trim());
        }

        if (!string.IsNullOrWhiteSpace(facts))
        {
            var formattedFacts = FormatFacts(facts);
            if (!string.IsNullOrWhiteSpace(formattedFacts))
            {
                parts.Add($"💡 Интересные факты:\n{formattedFacts}");
            }
        }

        if (!string.IsNullOrWhiteSpace(history))
        {
            var cleanedHistory = CleanHistory(history);
            if (!string.IsNullOrWhiteSpace(cleanedHistory))
            {
                parts.Add($"📖 История:\n{cleanedHistory}");
            }
        }

        return parts.Count > 0 ? string.Join("\n\n", parts) : null;
    }

    private static string? CleanPublisher(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var cleaned = CommaSpacingRegex().Replace(value.Trim(), ", ");
        return string.IsNullOrWhiteSpace(cleaned) ? null : cleaned;
    }

    private static string? ExtractAgeRating(string html)
    {
        var raw = ExtractLabeledValue(html, "Возрастные ограничения")
            ?? ExtractLabeledValue(html, "Возрастное ограничение");
        if (!string.IsNullOrWhiteSpace(raw))
        {
            var match = AgeRatingRegex().Match(raw);
            return match.Success ? match.Value : raw.Trim();
        }

        var directMatch = DirectAgeRatingRegex().Match(html);
        return directMatch.Success ? directMatch.Groups[1].Value : null;
    }

    /// <summary>Inner HTML of the first element matched by <paramref name="openingTag"/>, balancing nesting.</summary>
    private static string? InnerHtmlOf(string html, Regex openingTag)
    {
        var open = openingTag.Match(html);
        if (!open.Success) return null;
        var tagMatch = TagNameRegex().Match(open.Value);
        if (!tagMatch.Success) return null;

        var tag = tagMatch.Groups[1].Value;
        var contentStart = open.Index + open.Length;
        var depth = 1;
        var tokens = Regex.Matches(
            html[contentStart..],
            $"""<\s*(/?)\s*{Regex.Escape(tag)}\b[^>]*>""",
            RegexOptions.IgnoreCase);
        foreach (Match token in tokens)
        {
            if (token.Groups[1].Value == "/")
            {
                depth--;
                if (depth == 0) return html.Substring(contentStart, token.Index);
            }
            else if (!token.Value.TrimEnd().EndsWith("/>", StringComparison.Ordinal))
            {
                depth++;
            }
        }

        return null;
    }

    /// <summary>Value of a "Label: value" row, either the structured two-paragraph markup or plain text.</summary>
    private static string? ExtractLabeledValue(string html, string label)
    {
        var escaped = Regex.Escape(label);
        var structured = Regex.Match(
            html,
            $"""<p[^>]*>\s*{escaped}(?:<!-- -->)?:\s*</p>\s*<p[^>]*>(.*?)</p>""",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (structured.Success)
        {
            var structuredValue = HtmlToText(structured.Groups[1].Value);
            if (!string.IsNullOrWhiteSpace(structuredValue)) return structuredValue;
        }

        var plain = Regex.Match(
            html,
            $"""{escaped}(?:<!-- -->)?:\s*([^<\r\n]+)""",
            RegexOptions.IgnoreCase);
        return plain.Success ? HtmlToText(plain.Groups[1].Value) : null;
    }

    /// <summary>The illustrator row ("илл. Антонио Лоренте") as key staff.</summary>
    private static IReadOnlyList<ExternalStaffMemberDto>? ExtractStaff(string html)
    {
        var match = IllustratorRegex().Match(html);
        if (!match.Success) return null;
        var name = HtmlToText(match.Groups[1].Value);
        return string.IsNullOrWhiteSpace(name)
            ? null
            : [new ExternalStaffMemberDto(name, "Иллюстратор", null)];
    }

    /// <summary>HTML fragment to readable text: tags dropped, entities decoded, paragraphs kept.</summary>
    private static string? HtmlToText(string? fragment)
    {
        if (string.IsNullOrWhiteSpace(fragment)) return null;
        var text = Regex.Replace(fragment, """<br\s*/?>|</(?:p|div|li)\s*>""", "\n",
            RegexOptions.IgnoreCase);
        text = Regex.Replace(text, "<[^>]+>", " ");
        text = DecodeHtml(text);
        text = Regex.Replace(text, @"[ \t\f\v]+", " ");
        text = Regex.Replace(text, @" *\n *", "\n");
        text = Regex.Replace(text, @"\n{3,}", "\n\n");
        return text.Trim();
    }

    /// <summary>schema.org bookFormat URL/text to the Russian binding label.</summary>
    private static string? FormatOf(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (value.Contains("Hardcover", StringComparison.OrdinalIgnoreCase)) return "Твёрдый переплёт";
        if (value.Contains("Paperback", StringComparison.OrdinalIgnoreCase)) return "Мягкая обложка";
        return value.Trim();
    }

    private static IReadOnlyList<string> StringArrayProperty(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return [];
        return value.ValueKind switch
        {
            JsonValueKind.Array => value.EnumerateArray()
                .Select(item => item.ValueKind == JsonValueKind.Object
                    ? StringProperty(item, "name")
                    : NullIfBlank(item.ToString()))
                .Where(item => item is not null)
                .Select(item => item!)
                .ToList(),
            JsonValueKind.String => NullIfBlank(value.GetString()) is { } single ? [single] : [],
            _ => [],
        };
    }

    /// <summary>Image may be a string or an ImageObject with a <c>url</c>.</summary>
    private static string? ImageUrlProperty(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.String => NullIfBlank(value.GetString()),
            JsonValueKind.Object => StringProperty(value, "url"),
            JsonValueKind.Array => value.EnumerateArray()
                .Select(item => item.ValueKind == JsonValueKind.Object
                    ? StringProperty(item, "url")
                    : NullIfBlank(item.ToString()))
                .FirstOrDefault(item => item is not null),
            _ => null,
        };
    }

    private static double? TryDoubleProperty(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.Number => value.GetDouble(),
            JsonValueKind.String when double.TryParse(
                value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) => parsed,
            _ => null,
        };
    }

    private static int? TryIntProperty(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt32(out var parsed) => parsed,
            JsonValueKind.String when int.TryParse(value.GetString(), out var parsed) => parsed,
            _ => null,
        };
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

    [GeneratedRegex("""<script[^>]*type="application/ld\+json"[^>]*>\s*(\{.*?\})\s*</script>""",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex JsonLdRegex();

    [GeneratedRegex("""^(\d{4}-\d{2}-\d{2})""")]
    private static partial Regex DatePartRegex();

    [GeneratedRegex("""^(?:Книга\s+[«"].*?[»"]\.\s*Автор:|Предлагаем вашему вниманию книгу)""",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex TemplateDescriptionRegex();

    [GeneratedRegex("""<([a-zA-Z0-9]+)[^>]*itemprop="description"[^>]*>""", RegexOptions.IgnoreCase)]
    private static partial Regex ItempropDescriptionRegex();

    [GeneratedRegex("""<([a-zA-Z0-9]+)[^>]*id="lenta-card__text-actions-description"[^>]*>""",
        RegexOptions.IgnoreCase)]
    private static partial Regex LentaDescriptionRegex();

    [GeneratedRegex("""<([a-zA-Z0-9]+)[^>]*class="[^"]*(?:block-border|card-block)[^"]*"[^>]*>""",
        RegexOptions.IgnoreCase)]
    private static partial Regex CardDescriptionRegex();

    [GeneratedRegex("""<([a-zA-Z0-9]+)[^>]*class="[^"]*ShortInfoDescription[^"]*"[^>]*>""", RegexOptions.IgnoreCase)]
    private static partial Regex ShortInfoDescriptionRegex();

    [GeneratedRegex("""<([a-zA-Z0-9]+)[^>]*class="[^"]*TruncateContent[^"]*"[^>]*>""", RegexOptions.IgnoreCase)]
    private static partial Regex TruncateContentRegex();

    [GeneratedRegex(@"\\""artDescription\\""\s*:\s*\\""((?:\\\\|\\""|[^""\\])*)\\""", RegexOptions.Singleline)]
    private static partial Regex ArtDescriptionRegex();

    [GeneratedRegex("""<h3[^>]*>\s*Интересные\s+факты\s*</h3>\s*(.+?)(?=<div[^>]*>\s*<h3|</div>\s*</div>|<button|</main|$)""", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex FactsSectionRegex();

    [GeneratedRegex("""<h3[^>]*>\s*История(?:\s+создания)?\s*</h3>\s*(.+?)(?=<div[^>]*>\s*<h3|</div>\s*</div>|<button|</main|$)""", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex HistorySectionRegex();

    [GeneratedRegex("""<h3[^>]*>\s*Экранизации\s*</h3>\s*(.+?)(?=<div[^>]*>\s*<h3|</div>\s*</div>|<button|</main|$)""", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex AdaptationsSectionRegex();

    [GeneratedRegex("""<button\b[^>]*>.*?</button>""", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex HtmlButtonRegex();

    [GeneratedRegex(@"^\s*\([сc]\)\s*", RegexOptions.IgnoreCase)]
    private static partial Regex AttributionRegex();

    [GeneratedRegex(@"^[-*•]\s*")]
    private static partial Regex BulletPrefixRegex();

    [GeneratedRegex(@"\s*,\s*")]
    private static partial Regex CommaSpacingRegex();

    [GeneratedRegex(@"\b\d+\+\b")]
    private static partial Regex AgeRatingRegex();

    [GeneratedRegex(@"(?:Возрастные ограничения|Возрастное ограничение)[^0-9\n]{0,30}(\d+\+)", RegexOptions.IgnoreCase)]
    private static partial Regex DirectAgeRatingRegex();

    [GeneratedRegex("""^<\s*([a-zA-Z0-9]+)""")]
    private static partial Regex TagNameRegex();

    [GeneratedRegex("""(?:илл\.|Иллюстратор:)\s*([^<\r\n]+)""", RegexOptions.IgnoreCase)]
    private static partial Regex IllustratorRegex();

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
