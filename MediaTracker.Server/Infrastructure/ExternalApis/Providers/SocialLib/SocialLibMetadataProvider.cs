using System.Globalization;
using System.Text;
using System.Text.Json;
using MediaTracker.Server.Features.Media.Import;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class SocialLibMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase(Source)
{
    private const string PrimaryBaseUrl = "https://api.cdnlibs.org/api/";
    private const string FallbackBaseUrl = "https://api2.mangalib.me/api/";
    private const string BrowserUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "sociallib",
        Name: "SocialLib",
        Description: "Единый источник каталогов MangaLib, RanobeLib и AnimeLib",
        MediaTypes: ["manga", "book", "anime"],
        BaseAddress: PrimaryBaseUrl,
        RequiresApiKey: false,
        OptionalApiKey: true,
        Priority: 4,
        CanonicalName: "SocialLib",
        Aliases: ["mangalib", "ranobelib", "animelib", "slashlib", "hentailib"],
        UserAgent: BrowserUserAgent);

    private readonly string _mediaType =
        serviceKey?.StartsWith("book", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.StartsWith("novel", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.StartsWith("ranobe", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.Contains(":ranobelib", StringComparison.OrdinalIgnoreCase) is true ||
        string.Equals(serviceKey, "ranobelib", StringComparison.OrdinalIgnoreCase)
            ? "book"
            : (serviceKey?.StartsWith("anime", StringComparison.OrdinalIgnoreCase) is true ||
               serviceKey?.Contains(":animelib", StringComparison.OrdinalIgnoreCase) is true ||
               string.Equals(serviceKey, "animelib", StringComparison.OrdinalIgnoreCase)
                ? "anime"
                : "manga");

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var cleaned = MediaTitleHelper.StripGarbageSuffixes(query);
        var effectiveQuery = !string.IsNullOrWhiteSpace(cleaned) ? cleaned : query;
        // The catalog answers 422 to fields[] on the search route: the list payload already
        // carries names/covers/slugs, and the heavy fields are fetched by the detail call.
        var url = $"{BasePath}?q={Uri.EscapeDataString(effectiveQuery)}&site_id[]={SiteId}";

        var json = await SendWithFallbackAsync(url, ct);
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        return ParseResults(json);
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        // ExternalId is the site's slug_url ("195--naruto"); the API's detail route answers only
        // to the bare slug, so the leading "{id}--" part is stripped.
        var slug = externalId;
        var dash = slug.IndexOf("--", StringComparison.Ordinal);
        if (dash > 0) slug = slug[(dash + 2)..];

        var url = $"{BasePath}/{Uri.EscapeDataString(slug)}?fields[]=summary&fields[]=genres&fields[]=authors&fields[]=rate&site_id[]={SiteId}";
        var json = await SendWithFallbackAsync(url, ct);

        if (!string.IsNullOrWhiteSpace(json))
        {
            try
            {
                using var doc = JsonDocument.Parse(json);
                var elem = doc.RootElement;
                if (elem.TryGetProperty("data", out var dataElem) && dataElem.ValueKind == JsonValueKind.Object)
                {
                    elem = dataElem;
                }
                var mapped = MapElement(elem);
                if (mapped is not null)
                {
                    return mapped;
                }
            }
            catch (JsonException)
            {
                // fallback to search
            }
        }

        if (string.IsNullOrWhiteSpace(title))
        {
            return null;
        }

        var results = await SearchAsync(title, ct);
        return results.FirstOrDefault(r => string.Equals(r.ExternalId, externalId, StringComparison.OrdinalIgnoreCase))
            ?? (results.Count > 0 ? results[0] : null);
    }

    /// <summary>Manga and novels live under /api/manga; AnimeLib has its own /api/anime tree.</summary>
    private string BasePath => _mediaType == "anime" ? "anime" : "manga";

    /// <summary>site_id narrows the shared catalog to one site: manga 1, novels 3, anime 5.</summary>
    private int SiteId => _mediaType switch
    {
        "book" => 3,
        "anime" => 5,
        _ => 1
    };

    private async Task<string?> SendWithFallbackAsync(string relativeUrl, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);

        // 1. Try primary host: api.cdnlibs.org
        try
        {
            using var request = CreateRequest(relativeUrl, PrimaryBaseUrl);
            using var response = await client.SendAsync(request, ct);
            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadAsStringAsync(ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Primary network error or timeout -> proceed to fallback host
        }

        // 2. Fallback to secondary host: api2.mangalib.me
        try
        {
            using var fallbackRequest = CreateRequest(relativeUrl, FallbackBaseUrl);
            using var fallbackResponse = await client.SendAsync(fallbackRequest, ct);
            if (fallbackResponse.IsSuccessStatusCode)
            {
                return await fallbackResponse.Content.ReadAsStringAsync(ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Both hosts failed
        }

        return null;
    }

    private HttpRequestMessage CreateRequest(string relativeUrl, string baseUrl)
    {
        var fullUri = new Uri(new Uri(baseUrl), relativeUrl);
        var request = new HttpRequestMessage(HttpMethod.Get, fullUri);

        var (siteId, referer, origin) = _mediaType switch
        {
            "book" => ("3", "https://ranobelib.me/", "https://ranobelib.me"),
            "anime" => ("5", "https://v5.animelib.org/", "https://v5.animelib.org"),
            _ => ("1", "https://mangalib.me/", "https://mangalib.me")
        };

        request.Headers.TryAddWithoutValidation("Site-Id", siteId);
        request.Headers.TryAddWithoutValidation("Referer", referer);
        request.Headers.TryAddWithoutValidation("Origin", origin);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");

        if (!request.Headers.Contains("User-Agent"))
        {
            request.Headers.TryAddWithoutValidation("User-Agent", BrowserUserAgent);
        }

        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua", "\"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"");
        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua-Mobile", "?0");
        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua-Platform", "\"Linux\"");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Dest", "empty");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Mode", "cors");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Site", "cross-site");

        var token = options.Value.GetKey("sociallib")
            ?? options.Value.GetKey(ImportOnlyKeySources.MangaLib)
            ?? options.Value.GetKey("ranobelib");

        if (!string.IsNullOrWhiteSpace(token))
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
        }

        return request;
    }

    private IReadOnlyList<ExternalMediaDto> ParseResults(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            {
                root = data;
            }

            if (root.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            var results = new List<ExternalMediaDto>();
            foreach (var elem in root.EnumerateArray())
            {
                var dto = MapElement(elem);
                if (dto is not null && !string.IsNullOrWhiteSpace(dto.Title))
                {
                    results.Add(dto);
                }
            }

            return results;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private ExternalMediaDto? MapElement(JsonElement elem)
    {
        if (elem.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var rusName = elem.TryGetProperty("rus_name", out var rp) && rp.ValueKind == JsonValueKind.String ? rp.GetString() : null;
        var name = elem.TryGetProperty("name", out var np) && np.ValueKind == JsonValueKind.String ? np.GetString() : null;
        var engName = elem.TryGetProperty("eng_name", out var ep) && ep.ValueKind == JsonValueKind.String ? ep.GetString() : null;
        var title = !string.IsNullOrWhiteSpace(rusName) ? rusName : (!string.IsNullOrWhiteSpace(name) ? name : engName ?? string.Empty);
        var origTitle = !string.IsNullOrWhiteSpace(name) && name != title ? name : engName;
        var romajiTitle = !string.IsNullOrWhiteSpace(engName) ? engName : name;

        var id = elem.TryGetProperty("slug_url", out var sp) && sp.ValueKind == JsonValueKind.String ? sp.GetString()
            : (elem.TryGetProperty("id", out var ip) ? ip.ToString() : string.Empty);

        int? siteId = null;
        if (elem.TryGetProperty("site_id", out var sidProp) && sidProp.TryGetInt32(out var sId))
        {
            siteId = sId;
        }
        else if (elem.TryGetProperty("site", out var siteProp) && siteProp.TryGetInt32(out var sId2))
        {
            siteId = sId2;
        }

        string type;
        string externalSource;
        string? mangaFormat = null;

        switch (siteId)
        {
            case 1:
                type = "manga";
                externalSource = "MangaLib";
                break;
            case 2:
                type = "manga";
                externalSource = "SlashLib";
                break;
            case 3:
                type = "book";
                mangaFormat = "light_novel";
                externalSource = "RanobeLib";
                break;
            case 4:
                type = "manga";
                externalSource = "HentaiLib";
                break;
            case 5:
                type = "anime";
                externalSource = "AnimeLib";
                break;
            default:
                type = _mediaType switch
                {
                    "book" => "book",
                    "anime" => "anime",
                    _ => "manga"
                };
                mangaFormat = type == "book" ? "light_novel" : null;
                externalSource = type switch
                {
                    "book" => "RanobeLib",
                    "anime" => "AnimeLib",
                    _ => "MangaLib"
                };
                break;
        }

        int? count = null;
        if (elem.TryGetProperty("chap_count", out var cp) && cp.TryGetInt32(out var c)) count = c;
        else if (elem.TryGetProperty("episodes_count", out var epCount) && epCount.TryGetInt32(out var ec)) count = ec;
        else if (elem.TryGetProperty("items_count", out var ipCount) && ipCount.TryGetInt32(out var ic)) count = ic;

        int? chapters = type != "anime" ? count : null;
        IReadOnlyList<ExternalEpisodeDto>? episodes = type == "anime" && count is > 0
            ? [.. Enumerable.Range(1, count.Value).Select(n => new ExternalEpisodeDto { Number = n, Title = $"Episode {n}" })]
            : null;

        var (rating, votes) = ExtractRating(elem);
        var ratings = rating.HasValue
            ? new List<ExternalRatingDto> { new() { Source = externalSource, Rating = rating.Value, Votes = votes } }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = id ?? string.Empty,
            ExternalSource = externalSource,
            Title = title,
            OriginalTitle = origTitle,
            RomajiTitle = romajiTitle,
            CoverUrl = ExtractCover(elem),
            Description = ExtractSummary(elem),
            Author = ExtractAuthors(elem),
            Type = type,
            MangaFormat = mangaFormat,
            TotalCount = count,
            Chapters = chapters,
            Episodes = episodes,
            Rating = rating,
            RatingVotes = votes,
            Ratings = ratings,
            Genres = ExtractGenres(elem)
        };
    }

    /// <summary>
    /// summary used to be a plain string; the API now returns a TipTap document
    /// ({ content: [ { content: [ { text } ] } ] }) — walk it and collect the text runs.
    /// </summary>
    private static string? ExtractSummary(JsonElement elem)
    {
        if (!elem.TryGetProperty("summary", out var sum)) return null;
        if (sum.ValueKind == JsonValueKind.String)
        {
            var str = sum.GetString();
            return string.IsNullOrWhiteSpace(str) ? null : str.Trim();
        }

        if (sum.ValueKind != JsonValueKind.Object) return null;

        var sb = new StringBuilder();
        WalkTipTap(sum, sb);
        var text = sb.ToString().Trim();
        return text.Length > 0 ? text : null;

        static void WalkTipTap(JsonElement node, StringBuilder builder)
        {
            switch (node.ValueKind)
            {
                case JsonValueKind.Object:
                    if (node.TryGetProperty("text", out var textProp) && textProp.ValueKind == JsonValueKind.String)
                    {
                        builder.Append(textProp.GetString());
                        return;
                    }
                    if (node.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var child in content.EnumerateArray())
                        {
                            WalkTipTap(child, builder);
                        }
                    }
                    break;
                case JsonValueKind.Array:
                    foreach (var child in node.EnumerateArray())
                    {
                        WalkTipTap(child, builder);
                    }
                    break;
            }
        }
    }

    private static string? ExtractCover(JsonElement elem)
    {
        if (elem.TryGetProperty("cover", out var cover))
        {
            if (cover.ValueKind == JsonValueKind.String)
                return NormalizeCoverUrl(cover.GetString());
            if (cover.ValueKind == JsonValueKind.Object)
            {
                foreach (var sub in new[] { "default", "md", "thumbnail" })
                {
                    if (cover.TryGetProperty(sub, out var subProp) && subProp.ValueKind == JsonValueKind.String)
                    {
                        var str = NormalizeCoverUrl(subProp.GetString());
                        if (!string.IsNullOrWhiteSpace(str)) return str;
                    }
                }
            }
        }
        return null;
    }

    /// <summary>
    /// The catalog sometimes serves relative upload paths or scheme-less hosts; the card renders
    /// them only as absolute https URLs pointing at the shared cover CDN.
    /// </summary>
    public static string? NormalizeCoverUrl(string? url)
    {
        var value = url?.Trim();
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (value.StartsWith("//", StringComparison.Ordinal)) return $"https:{value}";
        if (value.StartsWith("/uploads/", StringComparison.OrdinalIgnoreCase) || value.StartsWith("uploads/", StringComparison.OrdinalIgnoreCase))
        {
            return $"https://cover.imglib.info/{value.TrimStart('/')}";
        }

        return value;
    }

    private static (double? Score, int? Votes) ExtractRating(JsonElement elem)
    {
        // The new API shape: rating: { average: "9.35", votes: 15384 }. The legacy rate:* fields
        // stay as a fallback for older mirrors.
        if (elem.TryGetProperty("rating", out var rating) && rating.ValueKind == JsonValueKind.Object)
        {
            double? score = null;
            int? votes = null;
            if (rating.TryGetProperty("average", out var avg))
            {
                if (avg.ValueKind == JsonValueKind.String && double.TryParse(avg.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedStr))
                    score = Math.Round(parsedStr, 1);
                else if (avg.ValueKind == JsonValueKind.Number && avg.TryGetDouble(out var parsedNum))
                    score = Math.Round(parsedNum, 1);
            }

            if (rating.TryGetProperty("votes", out var v) && v.TryGetInt32(out var vt))
                votes = vt;

            if (score is not null || votes is not null)
            {
                return (score, votes);
            }
        }

        if (elem.TryGetProperty("rate", out var rate))
        {
            if (rate.ValueKind == JsonValueKind.Object)
            {
                double? score = null;
                int? votes = null;
                if (rate.TryGetProperty("value", out var val) && val.TryGetDouble(out var d))
                    score = Math.Round(d, 1);
                else if (rate.TryGetProperty("avg", out var avg) && avg.ValueKind == JsonValueKind.String && double.TryParse(avg.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedAvg))
                    score = Math.Round(parsedAvg, 1);

                if (rate.TryGetProperty("votes", out var v) && v.TryGetInt32(out var vt))
                    votes = vt;
                return (score, votes);
            }
            if (rate.ValueKind == JsonValueKind.Number && rate.TryGetDouble(out var num))
                return (Math.Round(num, 1), null);
        }
        return (null, null);
    }

    private static string? ExtractAuthors(JsonElement elem)
    {
        if (!elem.TryGetProperty("authors", out var authorsProp)) return null;
        if (authorsProp.ValueKind == JsonValueKind.Array)
        {
            var names = new List<string>();
            foreach (var a in authorsProp.EnumerateArray())
            {
                if (a.ValueKind == JsonValueKind.Object)
                {
                    if (a.TryGetProperty("name", out var nameProp) && nameProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(nameProp.GetString()))
                        names.Add(nameProp.GetString()!);
                    else if (a.TryGetProperty("rus_name", out var rusProp) && rusProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(rusProp.GetString()))
                        names.Add(rusProp.GetString()!);
                }
                else if (a.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(a.GetString()))
                {
                    names.Add(a.GetString()!);
                }
            }
            return names.Count > 0 ? string.Join(", ", names) : null;
        }
        return null;
    }

    private static List<string>? ExtractGenres(JsonElement elem)
    {
        if (!elem.TryGetProperty("genres", out var genresProp) || genresProp.ValueKind != JsonValueKind.Array) return null;
        var list = new List<string>();
        foreach (var g in genresProp.EnumerateArray())
        {
            if (g.ValueKind == JsonValueKind.Object)
            {
                if (g.TryGetProperty("name", out var nameProp) && nameProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(nameProp.GetString()))
                    list.Add(nameProp.GetString()!);
                else if (g.TryGetProperty("rus_name", out var rusProp) && rusProp.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(rusProp.GetString()))
                    list.Add(rusProp.GetString()!);
            }
            else if (g.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(g.GetString()))
            {
                list.Add(g.GetString()!);
            }
        }
        return list.Count > 0 ? list : null;
    }
}
