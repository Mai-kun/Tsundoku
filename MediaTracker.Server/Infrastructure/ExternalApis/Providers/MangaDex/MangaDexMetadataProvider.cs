using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.MangaDex;

public sealed class MangaDexMetadataProvider(
    IHttpClientFactory httpClientFactory,
    ILogger<MangaDexMetadataProvider>? logger = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "mangadex",
        Name: "MangaDex",
        Description: "Manga and Manhwa metadata, chapters, volumes & ratings provider",
        MediaTypes: ["manga"],
        BaseAddress: "https://api.mangadex.org/",
        Priority: 3,
        // MangaDex's bot wall answers a browser-looking User-Agent with an HTML challenge page
        // ("if this isn't a browser, don't send a browser UA"), which failed every search and
        // details call with a JSON parse error. A plain app UA passes clean.
        UserAgent: "Tsundoku/1.0");

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var escapedQuery = Uri.EscapeDataString(query);
        var url = $"manga?title={escapedQuery}&limit=10&includes[]=cover_art&includes[]=author&includes[]=artist&order[relevance]=desc";

        try
        {
            var res = await client.GetFromJsonAsync(url, AppJsonSerializerContext.Default.MdMangaListResponse, ct);
            if (res?.Data is null || res.Data.Count == 0)
            {
                return [];
            }

            // Fetch statistics (ratings) in batch
            var ids = res.Data.ConvertAll(d => d.Id);
            var stats = await GetBatchStatisticsAsync(client, ids, ct);

            return res.Data.ConvertAll(d => MapItem(d, stats.GetValueOrDefault(d.Id)));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (JsonException ex)
        {
            logger?.LogWarning(ex, "[MangaDex] Failed to parse search response for '{Query}', likely HTML/Cloudflare error: {Message}", query, ex.Message);
            return [];
        }
        catch (HttpRequestException ex)
        {
            logger?.LogWarning(ex, "[MangaDex] HTTP request failed for '{Query}': {Message}", query, ex.Message);
            return [];
        }
        catch (Exception ex)
        {
            logger?.LogWarning(ex, "[MangaDex] Search failed for '{Query}': {Message}", query, ex.Message);
            return [];
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);

        try
        {
            MdMangaData? manga = null;
            if (Guid.TryParse(externalId, out _))
            {
                var res = await client.GetFromJsonAsync($"manga/{externalId}?includes[]=cover_art&includes[]=author&includes[]=artist", AppJsonSerializerContext.Default.MdMangaSingleResponse, ct);
                manga = res?.Data;
            }

            if (manga is null && !string.IsNullOrWhiteSpace(title))
            {
                var searchList = await SearchAsync(title, ct);
                var match = searchList.FirstOrDefault(s => s.Title.Equals(title, StringComparison.OrdinalIgnoreCase))
                            ?? (searchList.Count > 0 ? searchList[0] : null);
                if (match is not null && Guid.TryParse(match.ExternalId, out _))
                {
                    var res = await client.GetFromJsonAsync($"manga/{match.ExternalId}?includes[]=cover_art&includes[]=author&includes[]=artist", AppJsonSerializerContext.Default.MdMangaSingleResponse, ct);
                    manga = res?.Data;
                }
            }

            if (manga is null)
            {
                return null;
            }

            var stats = await GetBatchStatisticsAsync(client, [manga.Id], ct);
            return MapItem(manga, stats.GetValueOrDefault(manga.Id));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger?.LogWarning(ex, "[MangaDex] Failed to get details for '{ExternalId}': {Message}", externalId, ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Related titles from MangaDex's official <c>GET /manga/{id}/relation</c> endpoint, where each
    /// entry carries its relation kind in <c>attributes.relation</c> and the neighbour as a
    /// <c>relationships[]</c> entity of type <c>manga</c>. MangaDex does not inline the neighbour's
    /// title, cover or rating — those need a second, batched <c>/manga?ids[]=</c> lookup, so this is
    /// two round trips instead of the one AniList makes. When the relation endpoint answers empty or
    /// unreadable, the legacy inline <c>relationships</c> of the details payload is parsed as a
    /// fallback, because an older mirror answer is still better than an empty Related tab.
    ///
    /// <paramref name="externalId"/> is only a MangaDex id when the row was added from MangaDex; a row
    /// added from AniList carries a numeric id that answers nothing here, hence the title fallback
    /// using the same cascade as <see cref="GetDetailsAsync"/>.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRelationDto>> GetRelationsAsync(
        string? externalId,
        CancellationToken ct,
        string? title = null)
    {
        var client = httpClientFactory.CreateClient(Id);

        try
        {
            var mangaId = await ResolveMangaIdAsync(client, externalId, title, ct);
            if (mangaId is null)
            {
                return [];
            }

            var links = await FetchRelationEndpointAsync(client, mangaId, ct)
                        ?? await FetchInlineRelationshipsAsync(client, mangaId, ct);

            if (links.Count == 0)
            {
                return [];
            }

            var details = await GetMangaByIdsAsync(
                client, links.Select(l => l.Id).ToList(), ct);
            var stats = await GetBatchStatisticsAsync(
                client, [.. links.Select(l => l.Id)], ct);

            var relations = new List<ExternalRelationDto>(links.Count);
            foreach (var (id, related) in links)
            {
                if (!details.TryGetValue(id, out var manga)
                    || manga.Attributes?.Title is not { Count: > 0 })
                {
                    continue;
                }

                relations.Add(new ExternalRelationDto(
                    MapRelationType(related),
                    MapItem(manga, stats.GetValueOrDefault(id))));
            }

            return relations;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    /// <summary>
    /// The official <c>/manga/{id}/relation</c> listing: one entry per related title with the kind in
    /// <c>attributes.relation</c>. Returns null (not empty) when the endpoint could not be read at
    /// all, so the caller can tell "no relations exist" from "this answer is unusable" and fall back
    /// to the inline relationships.
    /// </summary>
    private static async Task<List<(string Id, string? Related)>?> FetchRelationEndpointAsync(
        HttpClient client,
        string mangaId,
        CancellationToken ct)
    {
        try
        {
            var res = await client.GetFromJsonAsync(
                $"manga/{mangaId}/relation", AppJsonSerializerContext.Default.MdRelationListResponse, ct);

            // Order is kept as MangaDex reported it so prequels and sequels stay in reading order
            // rather than being alphabetised; the same id reached twice is only kept once.
            var links = new List<(string Id, string? Related)>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var entry in res?.Data ?? [])
            {
                var target = (entry?.Relationships ?? []).FirstOrDefault(rel =>
                    string.Equals(rel.Type, "manga", StringComparison.OrdinalIgnoreCase)
                    && !string.IsNullOrWhiteSpace(rel.Id));

                if (target is null || string.IsNullOrWhiteSpace(target.Id) || !seen.Add(target.Id))
                {
                    continue;
                }

                links.Add((target.Id, entry?.Attributes?.Relation));
            }

            return links;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // A failed relation call is unusable, not empty: null sends the caller to the fallback.
            return null;
        }
    }

    /// <summary>
    /// The legacy shape: <c>related</c> riding the relationship object itself
    /// (<c>{"type":"manga","related":"sequel"}</c>) inside the details payload. Kept as the fallback
    /// path for answers where the relation endpoint came back unreadable.
    /// </summary>
    private static async Task<List<(string Id, string? Related)>> FetchInlineRelationshipsAsync(
        HttpClient client,
        string mangaId,
        CancellationToken ct)
    {
        try
        {
            var res = await client.GetFromJsonAsync(
                $"manga/{mangaId}?includes[]=manga", AppJsonSerializerContext.Default.MdMangaSingleResponse, ct);

            var links = new List<(string Id, string? Related)>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var rel in res?.Data?.Relationships ?? [])
            {
                if (!string.Equals(rel.Type, "manga", StringComparison.OrdinalIgnoreCase)
                    || string.IsNullOrWhiteSpace(rel.Id)
                    || !seen.Add(rel.Id))
                {
                    continue;
                }

                links.Add((rel.Id, rel.Related));
            }

            return links;
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

    /// <summary>
    /// MangaDex's own relation vocabulary → the relation types the Related tab groups on. Anything
    /// MangaDex invents beyond this (doujinshi, contains, monochrome...) is reported as OTHER instead
    /// of being dropped: an unmapped row still is a real relation the user asked for.
    /// </summary>
    public static string MapRelationType(string? related) => related?.ToLowerInvariant() switch
    {
        "sequel" => "SEQUEL",
        "prequel" or "preserialization" => "PREQUEL",
        "spin_off" => "SPIN_OFF",
        "side_story" => "SIDE_STORY",
        "alternate_version" or "alternate" => "ALTERNATIVE",
        "adaptation" or "adapted_from" => "ADAPTATION",
        "character" => "CHARACTER",
        _ => "OTHER",
    };

    /// <summary>The MangaDex uuid when the row has one, otherwise a title lookup for rows added elsewhere.</summary>
    internal static async Task<string?> ResolveMangaIdAsync(
        HttpClient client,
        string? externalId,
        string? title,
        CancellationToken ct)
    {
        if (Guid.TryParse(externalId, out var id) && id != Guid.Empty)
        {
            return externalId;
        }

        if (string.IsNullOrWhiteSpace(title))
        {
            return null;
        }

        try
        {
            var res = await client.GetFromJsonAsync($"manga?title={Uri.EscapeDataString(title)}&limit=10", AppJsonSerializerContext.Default.MdMangaListResponse, ct);
            foreach (var manga in res?.Data ?? [])
            {
                var label = manga.Attributes?.Title?.Values
                    .FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));
                if (label?.Equals(title, StringComparison.OrdinalIgnoreCase) == true)
                {
                    return manga.Id;
                }
            }

            // An exact title match is rare for a translated row, so the first hit wins over nothing.
            return res?.Data?.FirstOrDefault(d => Guid.TryParse(d.Id, out _))?.Id;
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

    /// <summary>
    /// Batched <c>/manga?ids[]=</c> lookup, chunked because the endpoint caps the id list. MangaDex
    /// does not inline a relation's own title, cover or rating, so they all come from here.
    /// </summary>
    private static async Task<Dictionary<string, MdMangaData>> GetMangaByIdsAsync(
        HttpClient client,
        IReadOnlyList<string> ids,
        CancellationToken ct)
    {
        var found = new Dictionary<string, MdMangaData>(StringComparer.OrdinalIgnoreCase);

        try
        {
            const int chunkSize = 50;
            for (var offset = 0; offset < ids.Count; offset += chunkSize)
            {
                var chunk = ids.Skip(offset).Take(chunkSize).ToList();
                var query = string.Join("&", chunk.Select(id => $"ids[]={id}"));
                var res = await client.GetFromJsonAsync($"manga?{query}&includes[]=cover_art&limit={chunkSize}", AppJsonSerializerContext.Default.MdMangaListResponse, ct);

                foreach (var manga in res?.Data ?? [])
                {
                    if (!string.IsNullOrWhiteSpace(manga.Id))
                    {
                        found[manga.Id] = manga;
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Covers and ratings are decoration: without them the relation rows still render.
        }

        return found;
    }

    private static async Task<Dictionary<string, MdMangaStatistics>> GetBatchStatisticsAsync(
        HttpClient client,
        List<string> ids,
        CancellationToken ct)
    {
        if (ids.Count == 0) return [];

        try
        {
            var query = string.Join("&", ids.Select(id => $"manga[]={id}"));
            var res = await client.GetFromJsonAsync($"statistics/manga?{query}", AppJsonSerializerContext.Default.MdStatisticsResponse, ct);
            return res?.Statistics ?? [];
        }
        catch
        {
            return [];
        }
    }

    private static ExternalMediaDto MapItem(MdMangaData d, MdMangaStatistics? stat)
    {
        var attr = d.Attributes;

        // Title preference: en -> ja-ro -> first. ja-ro stays in the cascade as the display title of
        // an English-less record; the ja/ja-ro → OriginalTitle/RomajiTitle mapping below is where the
        // original-language special case belongs.
        string title = "Unknown Title";
        if (attr?.Title is { Count: > 0 })
        {
            title = LocalizedText.Pick(attr.Title, "en", "ja-ro") ?? title;
        }

        // Description preference: ru -> en -> whatever the dictionary carries. The preference order
        // lives in LocalizedText so a future system-language tiebreak does not get replayed here.
        var description = LocalizedText.Pick(attr?.Description, "ru", "en");

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
            if (raw is > 0)
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

        var genres = new List<string>();
        if (attr?.Tags is { Count: > 0 })
        {
            foreach (var tag in attr.Tags)
            {
                if (tag.Attributes?.Name != null &&
                    tag.Attributes.Name.TryGetValue("en", out var enName) &&
                    !string.IsNullOrWhiteSpace(enName))
                {
                    genres.Add(enName);
                }
            }
        }

        if (d.Relationships is { Count: > 0 })
        {
            foreach (var rel in d.Relationships)
            {
                if (rel.Type == "tag" && rel.Attributes is { } tagAttr && tagAttr.TryGetProperty("name", out var nameProp))
                {
                    if (nameProp.ValueKind == JsonValueKind.Object && nameProp.TryGetProperty("en", out var enProp))
                    {
                        var enVal = enProp.GetString();
                        if (!string.IsNullOrWhiteSpace(enVal))
                        {
                            genres.Add(enVal);
                        }
                    }
                    else if (nameProp.ValueKind == JsonValueKind.String)
                    {
                        var strVal = nameProp.GetString();
                        if (!string.IsNullOrWhiteSpace(strVal))
                        {
                            genres.Add(strVal);
                        }
                    }
                }
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
            MangaFormat = MangaFormats.FromOriginalLanguage(attr?.OriginalLanguage),
            ExternalSource = "MangaDex",
            Rating = ratingScore,
            RatingVotes = ratingVotes,
            Ratings = ratings.Count > 0 ? ratings : null,
            Genres = genres.Count > 0 ? genres.Distinct(StringComparer.OrdinalIgnoreCase).ToList() : null
        };
    }
}
