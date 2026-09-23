using System.Net.Http.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed partial class AniListMetadataProvider(
    [ServiceKey] string mediaType,
    IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    private const string GraphQLQuery = """
        query Search($search: String, $type: MediaType) {
          Page(perPage: 10) {
            media(search: $search, type: $type, sort: SEARCH_MATCH) {
              id
              title { romaji english native }
              description(asHtml: false)
              coverImage { extraLarge }
              startDate { year }
              episodes
              chapters
              volumes
              studios(isMain: true) { nodes { name } }
              staff(perPage: 1) { edges { node { name { full } } } }
            }
          }
        }
        """;

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("AniList");
        var payload = new
        {
            query = GraphQLQuery,
            variables = new { search = query, type = mediaType == "anime" ? "ANIME" : "MANGA" },
        };

        using var response = await client.PostAsJsonAsync("", payload, ct);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<AniListResponse>(ct);
        if (result?.Data?.Page?.Media is not { Count: > 0 } media)
        {
            return [];
        }

        return media.Select(item => new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            Title = item.Title?.English ?? item.Title?.Romaji ?? item.Title?.Native ?? string.Empty,
            OriginalTitle = item.Title?.Native,
            CoverUrl = item.CoverImage?.ExtraLarge,
            Description = item.Description is null ? null : HtmlTags().Replace(item.Description, string.Empty),
            ReleaseYear = item.StartDate?.Year,
            Type = mediaType,
            Author = mediaType == "manga" ? item.Staff?.Edges?.FirstOrDefault()?.Node?.Name?.Full : null,
            Studio = item.Studios?.Nodes?.FirstOrDefault()?.Name,
            TotalCount = mediaType == "anime" ? item.Episodes : item.Chapters ?? item.Volumes,
        }).ToList();
    }

    [GeneratedRegex("<[^>]+>")]
    private static partial Regex HtmlTags();

    private sealed record AniListResponse(AniListData? Data);

    private sealed record AniListData(AniListPage? Page);

    private sealed record AniListPage(List<AniListMedia>? Media);

    private sealed record AniListMedia(
        int Id,
        AniListTitle? Title,
        string? Description,
        AniListCoverImage? CoverImage,
        AniListDate? StartDate,
        int? Episodes,
        int? Chapters,
        int? Volumes,
        AniListStudios? Studios,
        AniListStaff? Staff);

    private sealed record AniListTitle(string? Romaji, string? English, string? Native);

    private sealed record AniListCoverImage(string? ExtraLarge);

    private sealed record AniListDate(int? Year);

    private sealed record AniListStudios(List<AniListStudio>? Nodes);

    private sealed record AniListStudio(string? Name);

    private sealed record AniListStaff(List<AniListStaffEdge>? Edges);

    private sealed record AniListStaffEdge(AniListStaffNode? Node);

    private sealed record AniListStaffNode(AniListName? Name);

    private sealed record AniListName(string? Full);
}
