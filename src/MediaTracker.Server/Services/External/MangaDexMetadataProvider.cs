using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MangaDexMetadataProvider(
    [ServiceKey] string? mediaType = null,
    IHttpClientFactory httpClientFactory = null!) : IMetadataProvider
{
    public string Id => "mangadex";
    public string Name => "MangaDex";
    public string Description => "Manga and Manhwa metadata, chapters, volumes & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["manga"];

    private readonly string _mediaType = mediaType ?? "manga";

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("MangaDex");
        var escapedQuery = Uri.EscapeDataString(query);
        var url = $"manga?title={escapedQuery}&limit=10&includes[]=cover_art&includes[]=author&includes[]=artist&order[relevance]=desc";

        try
        {
            var res = await client.GetFromJsonAsync<MdMangaListResponse>(url, ct);
            if (res?.Data is null || res.Data.Count == 0)
            {
                return [];
            }

            // Fetch statistics (ratings) in batch
            var ids = res.Data.Select(d => d.Id).ToList();
            var stats = await GetBatchStatisticsAsync(client, ids, ct);

            return res.Data
                .Select(d => MapItem(d, stats.GetValueOrDefault(d.Id)))
                .ToList();
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

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("MangaDex");

        try
        {
            MdMangaData? manga = null;
            if (Guid.TryParse(externalId, out _))
            {
                var res = await client.GetFromJsonAsync<MdMangaSingleResponse>($"manga/{externalId}?includes[]=cover_art&includes[]=author&includes[]=artist", ct);
                manga = res?.Data;
            }

            if (manga is null && !string.IsNullOrWhiteSpace(title))
            {
                var searchList = await SearchAsync(title, ct);
                var match = searchList.FirstOrDefault(s => s.Title.Equals(title, StringComparison.OrdinalIgnoreCase))
                            ?? searchList.FirstOrDefault();
                if (match is not null && Guid.TryParse(match.ExternalId, out _))
                {
                    var res = await client.GetFromJsonAsync<MdMangaSingleResponse>($"manga/{match.ExternalId}?includes[]=cover_art&includes[]=author&includes[]=artist", ct);
                    manga = res?.Data;
                }
            }

            if (manga is null)
            {
                return null;
            }

            var stats = await GetBatchStatisticsAsync(client, [manga.Id], ct);
            var (volCount, chapCount) = await GetAggregateVolumesAndChaptersAsync(client, manga.Id, ct);

            var item = MapItem(manga, stats.GetValueOrDefault(manga.Id));
            if (volCount.HasValue && (!item.Volumes.HasValue || item.Volumes.Value <= 0))
            {
                item = item with { Volumes = volCount.Value };
            }
            if (chapCount.HasValue && (!item.Chapters.HasValue || item.Chapters.Value <= 0))
            {
                item = item with
                {
                    Chapters = chapCount.Value,
                    TotalCount = item.TotalCount ?? chapCount.Value
                };
            }

            return item;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    private static async Task<Dictionary<string, MdMangaStatistics>> GetBatchStatisticsAsync(
        HttpClient client,
        IReadOnlyList<string> ids,
        CancellationToken ct)
    {
        if (ids.Count == 0) return [];

        try
        {
            var query = string.Join("&", ids.Select(id => $"manga[]={id}"));
            var res = await client.GetFromJsonAsync<MdStatisticsResponse>($"statistics/manga?{query}", ct);
            return res?.Statistics ?? [];
        }
        catch
        {
            return [];
        }
    }

    private static async Task<(int? Volumes, int? Chapters)> GetAggregateVolumesAndChaptersAsync(
        HttpClient client,
        string mangaId,
        CancellationToken ct)
    {
        try
        {
            var res = await client.GetFromJsonAsync<JsonDocument>($"manga/{mangaId}/aggregate", ct);
            if (res is null || !res.RootElement.TryGetProperty("volumes", out var volumesElem) || volumesElem.ValueKind != JsonValueKind.Object)
            {
                return (null, null);
            }

            int maxVol = 0;
            double maxChap = 0;

            foreach (var prop in volumesElem.EnumerateObject())
            {
                if (int.TryParse(prop.Name, out var v) && v > maxVol)
                {
                    maxVol = v;
                }

                if (prop.Value.TryGetProperty("chapters", out var chapsElem) && chapsElem.ValueKind == JsonValueKind.Object)
                {
                    foreach (var cProp in chapsElem.EnumerateObject())
                    {
                        if (double.TryParse(cProp.Name, System.Globalization.CultureInfo.InvariantCulture, out var c) && c > maxChap)
                        {
                            maxChap = c;
                        }
                    }
                }
            }

            int? finalVols = maxVol > 0 ? maxVol : null;
            int? finalChaps = maxChap > 0 ? (int)Math.Floor(maxChap) : null;
            return (finalVols, finalChaps);
        }
        catch
        {
            return (null, null);
        }
    }

    private static ExternalMediaDto MapItem(MdMangaData d, MdMangaStatistics? stat)
    {
        var attr = d.Attributes;

        // Title preference: en -> ja-ro -> first
        string title = "Unknown Title";
        if (attr?.Title != null && attr.Title.Count > 0)
        {
            if (attr.Title.TryGetValue("en", out var enTitle) && !string.IsNullOrWhiteSpace(enTitle))
                title = enTitle;
            else if (attr.Title.TryGetValue("ja-ro", out var roTitle) && !string.IsNullOrWhiteSpace(roTitle))
                title = roTitle;
            else
                title = attr.Title.Values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v)) ?? title;
        }

        // Description preference: ru -> en -> first
        string? description = null;
        if (attr?.Description != null && attr.Description.Count > 0)
        {
            if (attr.Description.TryGetValue("ru", out var ruDesc) && !string.IsNullOrWhiteSpace(ruDesc))
                description = ruDesc;
            else if (attr.Description.TryGetValue("en", out var enDesc) && !string.IsNullOrWhiteSpace(enDesc))
                description = enDesc;
            else
                description = attr.Description.Values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));
        }

        // Alt title (Original / Romaji)
        string? originalTitle = null;
        string? romajiTitle = null;
        if (attr?.AltTitles is { Count: > 0 })
        {
            foreach (var alt in attr.AltTitles)
            {
                if (originalTitle is null && alt.TryGetValue("ja", out var ja) && !string.IsNullOrWhiteSpace(ja))
                    originalTitle = ja;
                if (romajiTitle is null && alt.TryGetValue("ja-ro", out var jaro) && !string.IsNullOrWhiteSpace(jaro))
                    romajiTitle = jaro;
            }
            originalTitle ??= attr.AltTitles.FirstOrDefault()?.Values.FirstOrDefault();
        }

        // Author and Cover art from relationships
        string? author = null;
        string? coverUrl = null;
        if (d.Relationships is { Count: > 0 })
        {
            foreach (var rel in d.Relationships)
            {
                if (author is null && (rel.Type == "author" || rel.Type == "artist"))
                {
                    if (rel.Attributes is { } authAttr && authAttr.TryGetProperty("name", out var nameProp))
                    {
                        var name = nameProp.GetString();
                        if (!string.IsNullOrWhiteSpace(name))
                        {
                            author = name;
                        }
                    }
                }
                else if (coverUrl is null && rel.Type == "cover_art")
                {
                    if (rel.Attributes is { } covAttr && covAttr.TryGetProperty("fileName", out var fileProp))
                    {
                        var file = fileProp.GetString();
                        if (!string.IsNullOrWhiteSpace(file))
                        {
                            coverUrl = $"https://uploads.mangadex.org/covers/{d.Id}/{file}.512.jpg";
                        }
                    }
                }
            }
        }

        // Chapters & Volumes from attributes
        int? chapters = null;
        if (!string.IsNullOrWhiteSpace(attr?.LastChapter) && double.TryParse(attr.LastChapter, System.Globalization.CultureInfo.InvariantCulture, out var ch))
        {
            chapters = (int)Math.Floor(ch);
        }

        int? volumes = null;
        if (!string.IsNullOrWhiteSpace(attr?.LastVolume) && int.TryParse(attr.LastVolume, out var vl))
        {
            volumes = vl;
        }

        // Release status
        var status = attr?.Status?.ToLowerInvariant() switch
        {
            "ongoing" => "releasing",
            "completed" => "finished",
            "hiatus" => "hiatus",
            "cancelled" => "cancelled",
            _ => attr?.Status
        };

        // Rating
        double? ratingScore = null;
        int? ratingVotes = null;
        var ratings = new List<ExternalRatingDto>();

        if (stat?.Rating is not null)
        {
            var raw = stat.Rating.Bayesian ?? stat.Rating.Average;
            if (raw.HasValue && raw.Value > 0)
            {
                ratingScore = Math.Round(raw.Value, 1);
                if (stat.Rating.Distribution != null)
                {
                    ratingVotes = stat.Rating.Distribution.Values.Sum();
                }

                ratings.Add(new ExternalRatingDto
                {
                    Source = "MangaDex",
                    Rating = ratingScore.Value,
                    Votes = ratingVotes
                });
            }
        }

        return new ExternalMediaDto
        {
            ExternalId = d.Id,
            Title = title,
            OriginalTitle = originalTitle,
            RomajiTitle = romajiTitle,
            CoverUrl = coverUrl,
            Description = description,
            ReleaseYear = attr?.Year,
            ReleaseDate = attr?.CreatedAt?.ToString("yyyy-MM-dd"),
            ReleaseStatus = status,
            Type = "manga",
            Author = author,
            TotalCount = chapters,
            Chapters = chapters,
            Volumes = volumes,
            ExternalSource = "MangaDex",
            Rating = ratingScore,
            RatingVotes = ratingVotes,
            Ratings = ratings.Count > 0 ? ratings : null
        };
    }

    private sealed class MdMangaListResponse
    {
        [JsonPropertyName("data")]
        public List<MdMangaData>? Data { get; set; }
    }

    private sealed class MdMangaSingleResponse
    {
        [JsonPropertyName("data")]
        public MdMangaData? Data { get; set; }
    }

    private sealed class MdMangaData
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("attributes")]
        public MdMangaAttributes? Attributes { get; set; }

        [JsonPropertyName("relationships")]
        public List<MdRelationship>? Relationships { get; set; }
    }

    private sealed class MdMangaAttributes
    {
        [JsonPropertyName("title")]
        public Dictionary<string, string>? Title { get; set; }

        [JsonPropertyName("altTitles")]
        public List<Dictionary<string, string>>? AltTitles { get; set; }

        [JsonPropertyName("description")]
        public Dictionary<string, string>? Description { get; set; }

        [JsonPropertyName("lastVolume")]
        public string? LastVolume { get; set; }

        [JsonPropertyName("lastChapter")]
        public string? LastChapter { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }

        [JsonPropertyName("year")]
        public int? Year { get; set; }

        [JsonPropertyName("createdAt")]
        public DateTime? CreatedAt { get; set; }
    }

    private sealed class MdRelationship
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("attributes")]
        public JsonElement? Attributes { get; set; }
    }

    private sealed class MdStatisticsResponse
    {
        [JsonPropertyName("statistics")]
        public Dictionary<string, MdMangaStatistics>? Statistics { get; set; }
    }

    private sealed class MdMangaStatistics
    {
        [JsonPropertyName("rating")]
        public MdRating? Rating { get; set; }

        [JsonPropertyName("follows")]
        public int? Follows { get; set; }
    }

    private sealed class MdRating
    {
        [JsonPropertyName("average")]
        public double? Average { get; set; }

        [JsonPropertyName("bayesian")]
        public double? Bayesian { get; set; }

        [JsonPropertyName("distribution")]
        public Dictionary<string, int>? Distribution { get; set; }
    }
}
