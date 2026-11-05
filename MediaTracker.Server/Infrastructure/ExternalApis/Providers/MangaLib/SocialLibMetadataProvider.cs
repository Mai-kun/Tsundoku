using System.Globalization;
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
        Name: "SocialLib (MangaLib / RanobeLib / AnimeLib)",
        Description: "SocialLib (MangaLib, RanobeLib, AnimeLib) metadata and ratings provider",
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
        var url = $"manga?q={Uri.EscapeDataString(effectiveQuery)}&fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";

        var json = await SendWithFallbackAsync(url, ct);
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        return ParseResults(json);
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var url = $"manga/{Uri.EscapeDataString(externalId)}?fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";
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
            "anime" => ("5", "https://animelib.org/", "https://animelib.org"),
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
            Description = elem.TryGetProperty("summary", out var sump) && sump.ValueKind == JsonValueKind.String ? sump.GetString() : null,
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

    private static string? ExtractCover(JsonElement elem)
    {
        if (elem.TryGetProperty("cover", out var cover))
        {
            if (cover.ValueKind == JsonValueKind.String)
                return cover.GetString()?.Trim();
            if (cover.ValueKind == JsonValueKind.Object)
            {
                foreach (var sub in new[] { "default", "md", "thumbnail" })
                {
                    if (cover.TryGetProperty(sub, out var subProp) && subProp.ValueKind == JsonValueKind.String)
                    {
                        var str = subProp.GetString();
                        if (!string.IsNullOrWhiteSpace(str)) return str.Trim();
                    }
                }
            }
        }
        return null;
    }

    private static (double? Score, int? Votes) ExtractRating(JsonElement elem)
    {
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
