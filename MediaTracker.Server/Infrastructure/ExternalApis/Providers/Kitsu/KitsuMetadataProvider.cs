using System.Globalization;
using System.Net;
using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Kitsu;

public sealed class KitsuMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "kitsu",
        Name: "Kitsu",
        Description: "Anime and Manga ratings provider (community scores)",
        MediaTypes: ["anime", "manga", "book"],
        BaseAddress: "https://kitsu.io/api/",
        Priority: 3);

    private readonly string mediaType = serviceKey?.StartsWith("book", StringComparison.OrdinalIgnoreCase) is true
        ? "book"
        : (serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime");

    /// <summary>Kitsu stores novels and manga in one tree; only anime has its own.</summary>
    private string Category => mediaType is "manga" or "book" ? "manga" : "anime";

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        try
        {
            var endpoint = mediaType switch
            {
                "book" => $"edge/manga?filter%5Btext%5D={Uri.EscapeDataString(query)}&filter%5Bsubtype%5D=novel&page%5Blimit%5D=10",
                "manga" => $"edge/manga?filter%5Btext%5D={Uri.EscapeDataString(query)}&page%5Blimit%5D=10",
                _ => $"edge/anime?filter%5Btext%5D={Uri.EscapeDataString(query)}&page%5Blimit%5D=10"
            };
            var res = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.KitsuSearchResponse, ct);

            if (res?.Data is not { Count: > 0 } data)
            {
                return [];
            }

            return data.ConvertAll(MapItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(externalId))
        {
            var client = httpClientFactory.CreateClient(Id);
            try
            {
                var res = await client.GetFromJsonAsync(
                    $"edge/{Category}/{Uri.EscapeDataString(externalId)}",
                    AppJsonSerializerContext.Default.KitsuSingleResponse,
                    ct);

                if (res?.Data is not null)
                {
                    var dto = MapItem(res.Data);
                    return await EnrichRelatedAsync(client, res.Data, dto, ct);
                }
                return null;
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.TooManyRequests)
            {
                throw;
            }
            catch
            {
                return null;
            }
        }

        if (string.IsNullOrWhiteSpace(externalId) && !string.IsNullOrWhiteSpace(title))
        {
            var results = await SearchAsync(title, ct);
            return results.Count > 0 ? results[0] : null;
        }

        return null;
    }

    private ExternalMediaDto MapItem(KitsuData item)
    {
        var attr = item.Attributes;
        var titles = ExtractTitles(attr);

        // 69.58 is 6.9, not 7.0: a community score cut to one decimal, never rounded up — the
        // tenth of a point the site shows is the only honest part of a percentage score.
        double? rating = null;
        if (!string.IsNullOrWhiteSpace(attr?.AverageRating) &&
            double.TryParse(attr.AverageRating, NumberStyles.Any, CultureInfo.InvariantCulture, out var score) &&
            score > 0)
        {
            rating = Math.Floor(score / 10.0 * 10) / 10;
        }

        List<ExternalRatingDto>? ratings = rating.HasValue
            ? [new ExternalRatingDto { Source = "Kitsu", Rating = rating.Value, Votes = attr?.UserCount }]
            : null;

        int? releaseYear = null;
        if (!string.IsNullOrWhiteSpace(attr?.StartDate) &&
            DateTime.TryParse(attr.StartDate, out var sDate))
        {
            releaseYear = sDate.Year;
        }

        var isNovel = mediaType == "book" || string.Equals(attr?.Subtype, "novel", StringComparison.OrdinalIgnoreCase);

        return new ExternalMediaDto
        {
            ExternalId = item.Id ?? string.Empty,
            ExternalSource = "Kitsu",
            Type = mediaType,
            MangaFormat = isNovel ? "light_novel" : (mediaType == "manga" ? "manga" : null),
            Title = titles.Canonical,
            OriginalTitle = titles.Original,
            RomajiTitle = titles.Romaji,
            Synonyms = titles.Synonyms,
            Description = attr?.Synopsis,
            CoverUrl = attr?.PosterImage?.Large ?? attr?.PosterImage?.Original,
            TotalCount = mediaType == "anime" ? attr?.EpisodeCount : (attr?.ChapterCount ?? attr?.VolumeCount),
            Chapters = attr?.ChapterCount,
            Volumes = attr?.VolumeCount,
            RuntimeMinutes = attr?.EpisodeLength,
            Rating = rating,
            RatingVotes = attr?.UserCount,
            Ratings = ratings,
            ReleaseDate = attr?.StartDate,
            EndDate = attr?.EndDate,
            ReleaseYear = releaseYear,
            ReleaseStatus = attr?.Status
        };
    }

    private sealed record KitsuTitles(string Canonical, string? Original, string? Romaji, List<string>? Synonyms);

    /// <summary>
    /// Every spelling the payload carries: the canonical title stays the display title, en_jp is
    /// the romaji, ja_jp the native name, and the remaining localized titles plus the abbreviated
    /// ones become synonyms. Duplicate spellings are dropped; the union with the other sources'
    /// variants happens later in the applier's AltTitles blob.
    /// </summary>
    private static KitsuTitles ExtractTitles(KitsuAttributes? attr)
    {
        var titles = attr?.Titles;
        var canonical = FirstNonEmpty(attr?.CanonicalTitle, Value(titles, "en_jp"), Value(titles, "en"), Value(titles, "en_us"))
            ?? "Unknown";
        var romaji = FirstNonEmpty(Value(titles, "en_jp"), attr?.CanonicalTitle);
        var original = FirstNonEmpty(Value(titles, "ja_jp"), Value(titles, "ja"));

        var synonyms = new List<string>();
        if (titles is not null)
        {
            synonyms.AddRange(titles.Values);
        }

        if (attr?.AbbreviatedTitles is { Count: > 0 } abbreviated)
        {
            synonyms.AddRange(abbreviated);
        }

        var known = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { canonical };
        if (romaji is not null) known.Add(romaji);
        if (original is not null) known.Add(original);

        var distinct = synonyms
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Where(known.Add)
            .ToList();

        return new KitsuTitles(
            canonical,
            original,
            romaji,
            distinct.Count > 0 ? distinct : null);

        static string? Value(Dictionary<string, string>? source, string key) =>
            source is not null && source.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value)
                ? value.Trim()
                : null;
    }

    private static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));

    /// <summary>
    /// Genres, categories, characters and staff ride behind the JSON:API "related" links the detail
    /// payload already carries, so one helper per shape fills them all: no per-field URL building.
    /// Each list is best-effort — a failing relationship must not sink the whole detail card.
    /// </summary>
    private async Task<ExternalMediaDto> EnrichRelatedAsync(
        HttpClient client, KitsuData item, ExternalMediaDto dto, CancellationToken ct)
    {
        var links = item.Relationships;

        var characterUrl = RelatedUrl(links, "characters");
        var castTask = FetchCastAsync(client, characterUrl, RelatedUrl(links, "castings"), ct);
        var staffTask = FetchStaffAsync(client, RelatedUrl(links, "staff"), ct);
        var genresTask = Task.WhenAll(
            FetchNamesAsync(client, RelatedUrl(links, "genres"), ct),
            FetchNamesAsync(client, RelatedUrl(links, "categories"), ct));

        await Task.WhenAll(castTask, staffTask, genresTask).WaitAsync(ct);
        var (cast, staff, genreLists) = (castTask.Result, staffTask.Result, genresTask.Result);
        var genres = genreLists[0].Concat(genreLists[1])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return dto with
        {
            Genres = genres.Count > 0 ? genres : dto.Genres,
            Cast = cast is { Count: > 0 } ? cast : dto.Cast,
            Staff = staff is { Count: > 0 } ? staff : dto.Staff,
        };
    }

    /// <summary>The relationship's own related URL when present, else the canonical route.</summary>
    private static string? RelatedUrl(Dictionary<string, KitsuRelNode>? relationships, string name)
    {
        var link = relationships is not null
            && relationships.TryGetValue(name, out var node)
            && node?.Links?.Related is { Length: > 0 } related
            ? related
            : null;
        if (link is null)
        {
            return null;
        }

        // The related link is a bare collection route; cap the payload and inline the resources
        // the cast/staff mappers read names from.
        var joiner = link.Contains('?', StringComparison.Ordinal) ? "&" : "?";
        return name is "castings" or "characters" or "staff"
            ? $"{link}{joiner}page%5Blimit%5D=12&include={IncludeFor(name)}"
            : $"{link}{joiner}page%5Blimit%5D=20";

        static string IncludeFor(string relation) => relation switch
        {
            "characters" => "character",
            "castings" => "person,character",
            _ => "person"
        };
    }

    private async Task<List<string>> FetchNamesAsync(HttpClient client, string? url, CancellationToken ct)
    {
        var names = new List<string>();
        if (url is null) return names;

        try
        {
            var res = await client.GetFromJsonAsync(url, AppJsonSerializerContext.Default.KitsuRelatedResponse, ct);
            foreach (var row in res?.Data ?? [])
            {
                var name = FirstNonEmpty(row.Attributes?.Name, row.Attributes?.Title);
                if (name is not null)
                {
                    names.Add(name);
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Genres are optional decoration on the detail card.
        }

        return names;
    }

    /// <summary>
    /// Characters become the cast for every media type; on anime the voice-actor castings override
    /// it with the fuller pair (character + seiyuu), matching how the AniList cast is stored.
    /// </summary>
    private async Task<IReadOnlyList<CastMemberDto>?> FetchCastAsync(
        HttpClient client, string? charactersUrl, string? castingsUrl, CancellationToken ct)
    {
        var characters = new List<CastMemberDto>();
        if (charactersUrl is not null)
        {
            try
            {
                var res = await client.GetFromJsonAsync(charactersUrl, AppJsonSerializerContext.Default.KitsuRelatedResponse, ct);
                var included = IndexIncluded(res?.Included);
                foreach (var row in res?.Data ?? [])
                {
                    var character = ResolveIncluded(included, row.Relationships, "character");
                    var name = FirstNonEmpty(
                        IncludedName(character),
                        row.Attributes?.Name);
                    if (name is null)
                    {
                        continue;
                    }

                    var imageUrl = IncludedImage(character);
                    characters.Add(new CastMemberDto(name, name, imageUrl)
                    {
                        CharacterImageUrl = imageUrl,
                        CharacterRole = row.Attributes?.Role?.ToUpperInvariant(),
                    });
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                // Characters stay optional.
            }
        }

        // Voice actors exist only in the castings list; a manga or novel has none and keeps the
        // character list as the cast.
        if (Category != "anime" || castingsUrl is null)
        {
            return characters.Count > 0 ? characters : null;
        }

        try
        {
            var res = await client.GetFromJsonAsync(castingsUrl, AppJsonSerializerContext.Default.KitsuRelatedResponse, ct);
            var included = IndexIncluded(res?.Included);
            var voiceCast = new List<CastMemberDto>();
            foreach (var row in res?.Data ?? [])
            {
                if (row.Attributes?.VoiceActor is not true)
                {
                    continue;
                }

                var person = ResolveIncluded(included, row.Relationships, "person");
                var character = ResolveIncluded(included, row.Relationships, "character");
                var vaName = FirstNonEmpty(IncludedName(person), row.Attributes?.Name);
                var charName = IncludedName(character);
                if (vaName is null && charName is null)
                {
                    continue;
                }

                var vaImage = IncludedImage(person);
                var charImage = IncludedImage(character);
                voiceCast.Add(new CastMemberDto(vaName ?? charName!, charName, vaImage ?? charImage)
                {
                    CharacterImageUrl = charImage,
                    CharacterRole = charName is null ? null : "MAIN",
                    VoiceActorName = vaName,
                    VoiceActorImageUrl = vaImage,
                });
            }

            if (voiceCast.Count > 0)
            {
                return voiceCast;
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Fall through to the plain character list.
        }

        return characters.Count > 0 ? characters : null;
    }

    private async Task<IReadOnlyList<ExternalStaffMemberDto>?> FetchStaffAsync(HttpClient client, string? url, CancellationToken ct)
    {
        if (url is null)
        {
            return null;
        }

        try
        {
            var res = await client.GetFromJsonAsync(url, AppJsonSerializerContext.Default.KitsuRelatedResponse, ct);
            var included = IndexIncluded(res?.Included);
            var staff = new List<ExternalStaffMemberDto>();
            foreach (var row in res?.Data ?? [])
            {
                var person = ResolveIncluded(included, row.Relationships, "person");
                var name = FirstNonEmpty(IncludedName(person), row.Attributes?.Name);
                if (name is null)
                {
                    continue;
                }

                staff.Add(new ExternalStaffMemberDto(name, row.Attributes?.Role, IncludedImage(person)));
            }

            return staff.Count > 0 ? staff : null;
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

    private static Dictionary<string, JsonElement> IndexIncluded(List<KitsuIncluded>? included)
    {
        var index = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var resource in included ?? [])
        {
            if (resource.Id is { Length: > 0 } id)
            {
                index[$"{resource.Type}:{id}"] = resource.Attributes;
            }
        }

        return index;
    }

    private static JsonElement? ResolveIncluded(
        Dictionary<string, JsonElement> index,
        Dictionary<string, KitsuRelNode>? relationships,
        string relationshipName)
    {
        if (relationships is null
            || !relationships.TryGetValue(relationshipName, out var node)
            || node?.Data?.Id is not { Length: > 0 } id)
        {
            return null;
        }

        return index.TryGetValue($"{node.Data.Type ?? relationshipName}:{id}", out var attributes) ? attributes : null;
    }

    private static string? IncludedName(JsonElement? attributes)
    {
        if (attributes is not { ValueKind: JsonValueKind.Object } attrs)
        {
            return null;
        }

        if (attrs.TryGetProperty("canonicalName", out var canonical) && canonical.ValueKind == JsonValueKind.String)
        {
            return NullIfEmpty(canonical.GetString());
        }

        if (attrs.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String)
        {
            return NullIfEmpty(name.GetString());
        }

        if (attrs.TryGetProperty("names", out var names) && names.ValueKind == JsonValueKind.Object)
        {
            foreach (var key in new[] { "en", "en_jp", "ja_jp" })
            {
                if (names.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
                {
                    return NullIfEmpty(value.GetString());
                }
            }
        }

        return null;
    }

    private static string? IncludedImage(JsonElement? attributes)
    {
        if (attributes is not { ValueKind: JsonValueKind.Object } attrs
            || !attrs.TryGetProperty("image", out var image)
            || image.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var key in new[] { "original", "large", "medium", "small", "tiny" })
        {
            if (image.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
            {
                return NullIfEmpty(value.GetString());
            }
        }

        return null;
    }

    private static string? NullIfEmpty(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>
    /// The Related tab's "load from Kitsu": the shared media-relationships table inlined with the
    /// destination titles, one request for the whole list.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRelationDto>> GetRelationsAsync(
        string? externalId,
        CancellationToken ct,
        string? title = null)
    {
        if (string.IsNullOrWhiteSpace(externalId))
        {
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);
        var sourceType = Category == "anime" ? "Anime" : "Manga";
        var url = $"edge/media-relationships?filter%5BsourceId%5D={Uri.EscapeDataString(externalId)}"
            + $"&filter%5BsourceType%5D={sourceType}&include=destination&page%5Blimit%5D=20";

        try
        {
            var res = await client.GetFromJsonAsync(
                url, AppJsonSerializerContext.Default.KitsuMediaRelationshipsResponse, ct);

            var index = IndexIncluded(res?.Included);
            var relations = new List<ExternalRelationDto>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var row in res?.Data ?? [])
            {
                var destination = row.Relationships is not null
                    && row.Relationships.TryGetValue("destination", out var node)
                    ? node?.Data
                    : null;
                if (destination?.Id is not { Length: > 0 } id || !seen.Add(id))
                {
                    continue;
                }

                if (!index.TryGetValue($"{destination.Type ?? sourceType.ToLowerInvariant()}:{id}", out var attributes)
                    || attributes.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }

                relations.Add(new ExternalRelationDto(
                    MapRelationType(row.Attributes?.Role),
                    MapDestination(id, destination.Type, attributes)));
            }

            return relations;
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

    private ExternalMediaDto MapDestination(string id, string? type, JsonElement attributes)
    {
        string? Str(string property) =>
            attributes.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
                ? NullIfEmpty(value.GetString())
                : null;

        var subtype = Str("subtype");
        var isNovel = string.Equals(subtype, "novel", StringComparison.OrdinalIgnoreCase);
        var destinationType = type == "anime" || (type is null && Category == "anime") ? "anime" : isNovel ? "book" : "manga";

        double? rating = null;
        if (Str("averageRating") is { } raw
            && double.TryParse(raw, NumberStyles.Any, CultureInfo.InvariantCulture, out var score)
            && score > 0)
        {
            rating = Math.Floor(score / 10.0 * 10) / 10;
        }

        string? cover = null;
        if (attributes.TryGetProperty("posterImage", out var poster) && poster.ValueKind == JsonValueKind.Object)
        {
            foreach (var key in new[] { "large", "original", "medium", "small" })
            {
                if (poster.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
                {
                    cover = NullIfEmpty(value.GetString());
                    if (cover is not null) break;
                }
            }
        }

        var titles = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (attributes.TryGetProperty("titles", out var titlesProp) && titlesProp.ValueKind == JsonValueKind.Object)
        {
            foreach (var entry in titlesProp.EnumerateObject())
            {
                if (entry.Value.ValueKind == JsonValueKind.String)
                {
                    titles[entry.Name] = entry.Value.GetString() ?? string.Empty;
                }
            }
        }

        var canonical = FirstNonEmpty(Str("canonicalTitle"), Str("slug")) ?? id;
        return new ExternalMediaDto
        {
            ExternalId = id,
            ExternalSource = "Kitsu",
            Type = destinationType,
            MangaFormat = isNovel ? "light_novel" : null,
            Title = canonical,
            RomajiTitle = titles.TryGetValue("en_jp", out var romaji) ? romaji : null,
            OriginalTitle = titles.TryGetValue("ja_jp", out var native) ? native : null,
            CoverUrl = cover,
            Rating = rating,
            ReleaseStatus = Str("status"),
        };
    }

    /// <summary>Kitsu's role vocabulary folded onto the labels the Related tab already renders.</summary>
    private static string MapRelationType(string? role) => role?.ToLowerInvariant().Replace('-', '_') switch
    {
        "sequel" => "SEQUEL",
        "prequel" or "parent_story" or "preserialization" => "PREQUEL",
        "spinoff" or "spin_off" => "SPIN_OFF",
        "side_story" => "SIDE_STORY",
        "alternative_version" or "alternative_setting" or "alternate_version" => "ALTERNATIVE",
        "adaptation" or "adapted_from" => "ADAPTATION",
        "summary" => "SUMMARY",
        "character" => "CHARACTER",
        _ => "OTHER",
    };
}
