using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Features.Media.Import;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class RanobeLibMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "ranobelib",
        Name: "RanobeLib",
        Description: "SocialLib Ranobe & Light Novel metadata provider",
        MediaTypes: ["book"],
        BaseAddress: "https://api.cdnlibs.org/api/",
        Priority: 4);

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var cleaned = MediaTitleHelper.StripGarbageSuffixes(query);
        var effectiveQuery = !string.IsNullOrWhiteSpace(cleaned) ? cleaned : query;
        var client = httpClientFactory.CreateClient(Id);
        var url = $"manga?site_id=3&q={Uri.EscapeDataString(effectiveQuery)}&fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";
        using var request = CreateRequest(url);

        try
        {
            using var response = await client.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                return [];
            }

            var json = await response.Content.ReadAsStringAsync(ct);
            return ParseResults(json);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return [];
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var url = $"manga/{Uri.EscapeDataString(externalId)}?fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";
        using var request = CreateRequest(url);

        try
        {
            using var response = await client.SendAsync(request, ct);
            if (response.IsSuccessStatusCode)
            {
                var json = await response.Content.ReadAsStringAsync(ct);
                using var doc = JsonDocument.Parse(json);
                var elem = doc.RootElement;
                if (elem.TryGetProperty("data", out var dataElem) && dataElem.ValueKind == JsonValueKind.Object)
                {
                    elem = dataElem;
                }
                return MapElement(elem);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // fallback to search
        }

        var results = await SearchAsync(title, ct);
        return results.FirstOrDefault(r => string.Equals(r.ExternalId, externalId, StringComparison.OrdinalIgnoreCase))
            ?? (results.Count > 0 ? results[0] : null);
    }

    private HttpRequestMessage CreateRequest(string relativeUrl)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, relativeUrl);
        request.Headers.TryAddWithoutValidation("Site-Id", "3");
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        request.Headers.TryAddWithoutValidation("Origin", "https://ranobelib.me");
        request.Headers.TryAddWithoutValidation("Referer", "https://ranobelib.me/");
        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua", "\"Chromium\";v=\"124\", \"Not-A.Brand\";v=\"99\"");
        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua-Mobile", "?0");
        request.Headers.TryAddWithoutValidation("Sec-Ch-Ua-Platform", "\"Linux\"");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Dest", "empty");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Mode", "cors");
        request.Headers.TryAddWithoutValidation("Sec-Fetch-Site", "cross-site");

        var token = options.Value.GetKey(ImportOnlyKeySources.MangaLib);
        if (!string.IsNullOrWhiteSpace(token))
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
        }

        return request;
    }

    private static IReadOnlyList<ExternalMediaDto> ParseResults(string json)
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

    private static ExternalMediaDto? MapElement(JsonElement elem)
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

        int? chapCount = elem.TryGetProperty("chap_count", out var cp) && cp.TryGetInt32(out var c) ? c : null;
        var (rating, votes) = ExtractRating(elem);
        var ratings = rating.HasValue
            ? new List<ExternalRatingDto> { new() { Source = "RanobeLib", Rating = rating.Value, Votes = votes } }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = id ?? string.Empty,
            ExternalSource = "RanobeLib",
            Title = title,
            OriginalTitle = origTitle,
            RomajiTitle = romajiTitle,
            CoverUrl = ExtractCover(elem),
            Description = elem.TryGetProperty("summary", out var sump) && sump.ValueKind == JsonValueKind.String ? sump.GetString() : null,
            Author = ExtractAuthors(elem),
            Type = "book",
            MangaFormat = "light_novel",
            TotalCount = chapCount,
            Chapters = chapCount,
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
