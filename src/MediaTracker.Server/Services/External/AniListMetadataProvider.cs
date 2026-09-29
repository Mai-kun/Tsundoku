using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed partial class AniListMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null) : IMetadataProvider
{
    public string Id => "anilist";
    public string Name => "AniList";
    public string Description => "Anime and Manga metadata & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["anime", "manga"];
    public bool IsDefault => true;

    private readonly string mediaType = serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) == true ? "manga" : "anime";

    private const string GraphQLSearchQuery = """
        query Search($search: String, $type: MediaType) {
          Page(perPage: 10) {
            media(search: $search, type: $type, sort: SEARCH_MATCH) {
              id
              title { romaji english native }
              description(asHtml: false)
              coverImage { extraLarge }
              startDate { year month day }
              endDate { year month day }
              status
              duration
              episodes
              chapters
              volumes
              averageScore
              meanScore
              streamingEpisodes { title }
              studios(isMain: true) { nodes { name } }
              staff(perPage: 5) { edges { role node { name { full } } } }
            }
          }
        }
        """;

    private const string GraphQLDetailQuery = """
        query Detail($id: Int, $type: MediaType) {
          Media(id: $id, type: $type) {
            id
            title { romaji english native }
            description(asHtml: false)
            coverImage { extraLarge }
            startDate { year month day }
            endDate { year month day }
            status
            duration
            episodes
            chapters
            volumes
            averageScore
            meanScore
            streamingEpisodes { title }
            studios(isMain: true) { nodes { name } }
            staff(perPage: 5) { edges { role node { name { full } } } }
          }
        }
        """;

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("AniList");
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

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        if (int.TryParse(externalId, out var id))
        {
            var client = httpClientFactory.CreateClient("AniList");
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
        return searchResults.FirstOrDefault();
    }

    private ExternalMediaDto MapItem(AniListMedia item)
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
            episodes = Enumerable.Range(1, item.Episodes.Value)
                .Select(n => new ExternalEpisodeDto { Number = n, Title = $"Episode {n}" })
                .ToList();
        }

        string? releaseDate = item.StartDate?.Year is { } sy
            ? $"{sy:D4}-{(item.StartDate.Month ?? 1):D2}-{(item.StartDate.Day ?? 1):D2}"
            : null;
        string? endDate = item.EndDate?.Year is { } ey
            ? $"{ey:D4}-{(item.EndDate.Month ?? 1):D2}-{(item.EndDate.Day ?? 1):D2}"
            : null;

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
            Type = mediaType,
            Author = mediaType == "manga"
                ? (item.Staff?.Edges?.FirstOrDefault(e => e.Role?.Contains("Story", StringComparison.OrdinalIgnoreCase) == true || e.Role?.Contains("Art", StringComparison.OrdinalIgnoreCase) == true)?.Node?.Name?.Full
                   ?? item.Staff?.Edges?.FirstOrDefault()?.Node?.Name?.Full)
                : null,
            Studio = item.Studios?.Nodes?.FirstOrDefault()?.Name,
            TotalCount = mediaType == "anime" ? item.Episodes : (item.Chapters ?? item.Volumes),
            Chapters = item.Chapters,
            Volumes = item.Volumes,
            Rating = primaryRating,
            Ratings = ratings,
            Episodes = episodes
        };
    }

    private async Task EnrichAnimeRatingsAsync(List<ExternalMediaDto> items, CancellationToken ct)
    {
        // Only enrich top 3 to keep search responsive
        var targets = items.Take(3).ToList();
        var client = httpClientFactory.CreateClient("Kitsu");

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

    private sealed record AniListSearchResponse(AniListData? Data);
    private sealed record AniListDetailResponse(AniListDetailData? Data);
    private sealed record AniListDetailData(AniListMedia? Media);
    private sealed record AniListData(AniListPage? Page);
    private sealed record AniListPage(List<AniListMedia>? Media);

    private sealed record AniListMedia(
        int Id,
        AniListTitle? Title,
        string? Description,
        AniListCoverImage? CoverImage,
        AniListDate? StartDate,
        AniListDate? EndDate,
        string? Status,
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
