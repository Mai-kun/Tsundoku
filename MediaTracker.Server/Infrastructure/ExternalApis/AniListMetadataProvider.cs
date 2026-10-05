using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Rules;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed partial class AniListMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "anilist",
        Name: "AniList",
        Description: "Anime and Manga metadata & ratings provider",
        MediaTypes: ["anime", "manga"],
        BaseAddress: "https://graphql.anilist.co/",
        IsDefault: true,
        Priority: 1);

    private readonly string mediaType = serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime";

    private const string MediaFields = """
        id
        type
        format
        title { romaji english native }
        description(asHtml: false)
        coverImage { extraLarge }
        startDate { year month day }
        endDate { year month day }
        status
        countryOfOrigin
        duration
        episodes
        chapters
        volumes
        averageScore
        meanScore
        streamingEpisodes { title }
        studios(isMain: true) { nodes { name } }
        staff(perPage: 5) { edges { role node { name { full } } } }
        """;

    private const string GraphQLSearchQuery = $$"""
        query Search($search: String, $type: MediaType) {
          Page(perPage: 10) {
            media(search: $search, type: $type, sort: SEARCH_MATCH) {
              {{MediaFields}}
            }
          }
        }
        """;

    private const string GraphQLDetailQuery = $$"""
        query Detail($id: Int, $type: MediaType) {
          Media(id: $id, type: $type) {
            {{MediaFields}}
          }
        }
        """;

    private const string GraphQLRelationsQuery = $$"""
        query Relations($id: Int, $idMal: Int, $search: String, $type: MediaType) {
          Media(id: $id, idMal: $idMal, search: $search, type: $type) {
            relations {
              edges {
                relationType
                node {
                  {{MediaFields}}
                }
              }
            }
          }
        }
        """;

    private const string GraphQLRecommendationsQuery = $$"""
        query Recommendations($id: Int, $idMal: Int, $search: String, $type: MediaType) {
          Media(id: $id, idMal: $idMal, search: $search, type: $type) {
            recommendations(sort: RATING_DESC, perPage: 12) {
              nodes {
                rating
                mediaRecommendation {
                  id
                  type
                  title { romaji english native }
                  coverImage { extraLarge }
                  averageScore
                }
              }
            }
          }
        }
        """;

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var payload = new
        {
            query = GraphQLSearchQuery,
            variables = new { search = query, type = mediaType == "anime" ? "ANIME" : "MANGA" },
        };

        using var response = await client.PostAsJsonAsync("", payload, ct);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<AniListSearchResponse>(ct);
        if (result?.Data?.Page?.Media is not { Count: > 0 } mediaList)
        {
            return [];
        }

        var dtoList = new List<ExternalMediaDto>();
        foreach (var item in mediaList)
        {
            var dto = MapItem(item);
            dtoList.Add(dto);
        }

        // For anime, enrich top results with Kitsu rating for multi-source anime ratings
        if (mediaType == "anime" && dtoList.Count > 0)
        {
            await EnrichAnimeRatingsAsync(dtoList, ct);
        }

        return dtoList;
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        if (int.TryParse(externalId, out var id))
        {
            var client = httpClientFactory.CreateClient(Id);
            var payload = new
            {
                query = GraphQLDetailQuery,
                variables = new { id, type = mediaType == "anime" ? "ANIME" : "MANGA" }
            };

            using var response = await client.PostAsJsonAsync("", payload, ct);
            if (response.IsSuccessStatusCode)
            {
                var result = await response.Content.ReadFromJsonAsync<AniListDetailResponse>(ct);
                if (result?.Data?.Media is { } item)
                {
                    var dto = MapItem(item);
                    var dtoList = new List<ExternalMediaDto> { dto };
                    if (mediaType == "anime")
                    {
                        await EnrichAnimeRatingsAsync(dtoList, ct);
                    }
                    return dtoList[0];
                }
            }
        }

        var searchResults = await SearchAsync(title, ct);
        return searchResults.Count > 0 ? searchResults[0] : null;
    }

    /// <summary>
    /// Related titles for this provider's own id, falling back to a MAL id and then to a title search.
    /// AniList resolves ids far more reliably than search, so the id wins and search is the last resort
    /// rather than the first — the same order the client used before this moved server-side.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRelationDto>> GetRelationsAsync(
        string? externalId,
        bool externalIdIsMal,
        string? title,
        CancellationToken ct)
    {
        var edges = (await QueryAsync<AniListRelationsResponse, AniListRelationsData>(
                GraphQLRelationsQuery,
                LookupVariables(externalId, externalIdIsMal, title),
                ct)
            ?? await QueryAsync<AniListRelationsResponse, AniListRelationsData>(
                GraphQLRelationsQuery,
                SearchOnly(title),
                ct))?.Media?.Relations?.Edges ?? [];

        var relations = new List<ExternalRelationDto>();
        foreach (var edge in edges)
        {
            if (edge?.Node is not { } node || !HasTitle(node))
            {
                continue;
            }

            relations.Add(new ExternalRelationDto(
                edge.RelationType ?? "OTHER",
                MapItem(node, NormalizeType(node.Type))));
        }

        return relations;
    }

    /// <summary>
    /// What AniList itself recommends for this title, best-rated first. Same lookup cascade as
    /// <see cref="GetRelationsAsync"/>.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRecommendationDto>> GetRecommendationsAsync(
        string? externalId,
        bool externalIdIsMal,
        string? title,
        CancellationToken ct)
    {
        var nodes = (await QueryAsync<AniListRecommendationsResponse, AniListRecommendationsData>(
                GraphQLRecommendationsQuery,
                LookupVariables(externalId, externalIdIsMal, title),
                ct)
            ?? await QueryAsync<AniListRecommendationsResponse, AniListRecommendationsData>(
                GraphQLRecommendationsQuery,
                SearchOnly(title),
                ct))?.Media?.Recommendations?.Nodes ?? [];

        return
        [
            .. nodes
                .Select(node => node?.MediaRecommendation)
                .Where(media => media is not null && !string.IsNullOrWhiteSpace(media.Title?.English ?? media.Title?.Romaji ?? media.Title?.Native))
                .Select(media => new ExternalRecommendationDto(
                    media!.Id.ToString(),
                    media.Title?.English ?? media.Title?.Romaji ?? media.Title?.Native!,
                    media.CoverImage?.ExtraLarge,
                    // AniList scores 0..100; the whole app stores 0..10.
                    media.AverageScore is > 0 ? Math.Round(media.AverageScore.Value / 10.0, 1) : null,
                    Source.Name))
        ];
    }

    private string GraphQlType => mediaType == "manga" ? "MANGA" : "ANIME";

    private static bool HasTitle(AniListMedia node) =>
        !string.IsNullOrWhiteSpace(node.Title?.English ?? node.Title?.Romaji ?? node.Title?.Native);

    /// <summary>
    /// The id lookup wins when the row carries one; <c>search</c> is always sent alongside it so a miss
    /// can be retried by title instead of reporting the title as having nothing.
    /// </summary>
    private Dictionary<string, object> LookupVariables(string? externalId, bool externalIdIsMal, string? title)
    {
        var variables = new Dictionary<string, object> { ["type"] = GraphQlType, ["search"] = title ?? string.Empty };
        if (int.TryParse(externalId, out var numeric))
        {
            variables[externalIdIsMal ? "idMal" : "id"] = numeric;
        }

        return variables;
    }

    private Dictionary<string, object> SearchOnly(string? title) =>
        new() { ["type"] = GraphQlType, ["search"] = title ?? string.Empty };

    /// <summary>
    /// One GraphQL round trip, or null when the provider could not be reached. AniList answers 200 with
    /// an <c>errors</c> array for a rejected query, so failures are reported as "no data" rather than as
    /// exceptions for each caller to catch — the same trade-off the rating enrichment above already makes.
    /// </summary>
    private async Task<TData?> QueryAsync<TResponse, TData>(
        string query,
        Dictionary<string, object> variables,
        CancellationToken ct)
        where TResponse : class, IAniListEnvelope<TData>
        where TData : class
    {
        try
        {
            using var response = await httpClientFactory.CreateClient(Id).PostAsJsonAsync(
                "",
                new { query, variables },
                ct);

            return response.IsSuccessStatusCode
                ? (await response.Content.ReadFromJsonAsync<TResponse>(ct))?.Data
                : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return null;
        }
    }

    private interface IAniListEnvelope<TData>
        where TData : class
    {
        TData? Data { get; }
    }

    private static string NormalizeType(string? aniListType) =>
        aniListType?.Equals("MANGA", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime";

    private ExternalMediaDto MapItem(AniListMedia item) => MapItem(item, mediaType);

    private ExternalMediaDto MapItem(AniListMedia item, string type)
    {
        var primaryRating = item.AverageScore is { } score && score > 0
            ? Math.Round(score / 10.0, 1)
            : (double?)null;

        var ratings = new List<ExternalRatingDto>();
        if (primaryRating is not null)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "AniList",
                Rating = primaryRating.Value
            });
        }

        var episodes = item.StreamingEpisodes?
            .Select((ep, idx) => new ExternalEpisodeDto
            {
                Number = idx + 1,
                Title = ep.Title ?? $"Episode {idx + 1}"
            })
            .ToList();

        // If no streaming episodes returned, but episodes count > 0, generate placeholders
        if ((episodes == null || episodes.Count == 0) && item.Episodes is > 0)
        {
            episodes = [.. Enumerable.Range(1, item.Episodes.Value)
                .Select(n => new ExternalEpisodeDto { Number = n, Title = $"Episode {n}" })];
        }

        // A source that only knows the year must not be rendered as "1 Jan": the GraphQL client fills the
        // missing month/day with 1, so we build the shortest date the source actually vouches for.
        string? releaseDate = FormatPartialDate(item.StartDate?.Year, item.StartDate?.Month, item.StartDate?.Day);
        string? endDate = FormatPartialDate(item.EndDate?.Year, item.EndDate?.Month, item.EndDate?.Day);

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            ExternalSource = "AniList",
            Title = item.Title?.English ?? item.Title?.Romaji ?? item.Title?.Native ?? string.Empty,
            OriginalTitle = item.Title?.Native ?? item.Title?.Romaji,
            RomajiTitle = item.Title?.Romaji ?? item.Title?.English,
            CoverUrl = item.CoverImage?.ExtraLarge,
            Description = item.Description is null ? null : HtmlTags().Replace(item.Description, string.Empty),
            ReleaseYear = item.StartDate?.Year,
            ReleaseDate = releaseDate,
            EndDate = endDate,
            ReleaseStatus = item.Status,
            RuntimeMinutes = item.Duration,
            Type = type,
            Format = item.Format,
            Author = type == "manga"
                ? (item.Staff?.Edges?.FirstOrDefault(e => e.Role?.Contains("Story", StringComparison.OrdinalIgnoreCase) is true || e.Role?.Contains("Art", StringComparison.OrdinalIgnoreCase) is true)?.Node?.Name?.Full
                   ?? item.Staff?.Edges?.FirstOrDefault()?.Node?.Name?.Full)
                : null,
            Studio = item.Studios?.Nodes?.FirstOrDefault()?.Name,
            TotalCount = type == "anime" ? item.Episodes : (item.Chapters ?? item.Volumes),
            Chapters = item.Chapters,
            Volumes = item.Volumes,
            MangaFormat = type == "manga" ? MangaFormats.FromCountryOfOrigin(item.CountryOfOrigin) : null,
            Rating = primaryRating,
            Ratings = ratings,
            Episodes = episodes
        };
    }

    private async Task EnrichAnimeRatingsAsync(List<ExternalMediaDto> items, CancellationToken ct)
    {
        // Only enrich top 3 to keep search responsive
        var targets = items.Take(3).ToList();
        var client = httpClientFactory.CreateClient("kitsu");

        var tasks = targets.Select(async dto =>
        {
            try
            {
                using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                cts.CancelAfter(TimeSpan.FromSeconds(2));
                var queryTitle = !string.IsNullOrWhiteSpace(dto.OriginalTitle) ? dto.OriginalTitle : dto.Title;
                var res = await client.GetFromJsonAsync<KitsuSearchResponse>(
                    $"edge/anime?filter[text]={Uri.EscapeDataString(queryTitle)}&page[limit]=1", cts.Token);

                if (res?.Data?.FirstOrDefault()?.Attributes is { } attr &&
                    !string.IsNullOrWhiteSpace(attr.AverageRating) &&
                    double.TryParse(attr.AverageRating, System.Globalization.CultureInfo.InvariantCulture, out var kitsuScore) &&
                    kitsuScore > 0)
                {
                    var kitsuRating = Math.Round(kitsuScore / 10.0, 1);
                    var list = dto.Ratings is not null ? new List<ExternalRatingDto>(dto.Ratings) : [];
                    if (!list.Any(r => r.Source == "Kitsu"))
                    {
                        list.Add(new ExternalRatingDto
                        {
                            Source = "Kitsu",
                            Rating = kitsuRating,
                            Votes = attr.UserCount
                        });
                    }

                    // Mutate with enriched ratings
                    var index = items.IndexOf(dto);
                    if (index >= 0)
                    {
                        items[index] = dto with { Ratings = list };
                    }
                }
            }
            catch
            {
                // Non-fatal if Kitsu fails/times out
            }
        });

        await Task.WhenAll(tasks);
    }

    [GeneratedRegex("<[^>]+>")]
    private static partial Regex HtmlTags();

    /// <summary>Shortest date the source actually vouches for: year, year+month, or a full date.</summary>
    private static string? FormatPartialDate(int? year, int? month, int? day)
    {
        if (year is not { } y) return null;
        if (month is not { } m) return $"{y:D4}";
        if (day is not { } d) return $"{y:D4}-{m:D2}";
        return $"{y:D4}-{m:D2}-{d:D2}";
    }

    private sealed record AniListSearchResponse(AniListData? Data);
    private sealed record AniListDetailResponse(AniListDetailData? Data);
    private sealed record AniListDetailData(AniListMedia? Media);
    private sealed record AniListData(AniListPage? Page);
    private sealed record AniListPage(List<AniListMedia>? Media);

    private sealed record AniListRelationsResponse(AniListRelationsData? Data)
        : IAniListEnvelope<AniListRelationsData>;

    private sealed record AniListRelationsData(AniListRelationsPayload? Media);

    private sealed record AniListRelationsPayload(AniListRelationEdges? Relations);

    private sealed record AniListRelationEdges(List<AniListRelationEdge?>? Edges);

    private sealed record AniListRelationEdge(string? RelationType, AniListMedia? Node);

    private sealed record AniListRecommendationsResponse(AniListRecommendationsData? Data)
        : IAniListEnvelope<AniListRecommendationsData>;

    private sealed record AniListRecommendationsData(AniListRecommendationsPayload? Media);

    private sealed record AniListRecommendationsPayload(AniListRecommendationNodes? Recommendations);

    private sealed record AniListRecommendationNodes(List<AniListRecommendationNode?>? Nodes);

    private sealed record AniListRecommendationNode(double? Rating, AniListRecommendedMedia? MediaRecommendation);

    private sealed record AniListRecommendedMedia(
        int Id,
        string? Type,
        AniListTitle? Title,
        AniListCoverImage? CoverImage,
        int? AverageScore);

    private sealed record AniListMedia(
        int Id,
        string? Type,
        string? Format,
        AniListTitle? Title,
        string? Description,
        AniListCoverImage? CoverImage,
        AniListDate? StartDate,
        AniListDate? EndDate,
        string? Status,
        string? CountryOfOrigin,
        int? Duration,
        int? Episodes,
        int? Chapters,
        int? Volumes,
        int? AverageScore,
        int? MeanScore,
        List<AniListStreamingEpisode>? StreamingEpisodes,
        AniListStudios? Studios,
        AniListStaff? Staff);

    private sealed record AniListStreamingEpisode(string? Title);
    private sealed record AniListTitle(string? Romaji, string? English, string? Native);
    private sealed record AniListCoverImage(string? ExtraLarge);
    private sealed record AniListDate(int? Year, int? Month, int? Day);
    private sealed record AniListStudios(List<AniListStudio>? Nodes);
    private sealed record AniListStudio(string? Name);
    private sealed record AniListStaff(List<AniListStaffEdge>? Edges);
    private sealed record AniListStaffEdge(string? Role, AniListStaffNode? Node);
    private sealed record AniListStaffNode(AniListName? Name);
    private sealed record AniListName(string? Full);

    private sealed record KitsuSearchResponse(List<KitsuData>? Data);
    private sealed record KitsuData(KitsuAttributes? Attributes);
    private sealed record KitsuAttributes(
        [property: JsonPropertyName("canonicalTitle")] string? CanonicalTitle,
        [property: JsonPropertyName("averageRating")] string? AverageRating,
        [property: JsonPropertyName("userCount")] int? UserCount);
}
