using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Services.External;

public sealed class OpenLibraryMetadataProvider(IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("OpenLibrary");

        var result = await client.GetFromJsonAsync<OpenLibraryResponse>(
            $"search.json?q={Uri.EscapeDataString(query)}&limit=10", ct);

        if (result?.Docs is not { Count: > 0 } docs)
        {
            return [];
        }

        return docs.Select(doc => new ExternalMediaDto
        {
            ExternalId = doc.Key ?? string.Empty,
            Title = doc.Title ?? string.Empty,
            CoverUrl = doc.CoverId is { } coverId
                ? $"https://covers.openlibrary.org/b/id/{coverId}-L.jpg"
                : null,
            ReleaseYear = doc.FirstPublishYear,
            Type = "book",
            Author = doc.AuthorName?.FirstOrDefault(),
            TotalCount = doc.NumberOfPagesMedian,
        }).ToList();
    }

    private sealed record OpenLibraryResponse(List<OpenLibraryDoc>? Docs);

    private sealed record OpenLibraryDoc(
        string? Key,
        string? Title,
        [property: JsonPropertyName("author_name")] List<string>? AuthorName,
        [property: JsonPropertyName("cover_i")] int? CoverId,
        [property: JsonPropertyName("first_publish_year")] int? FirstPublishYear,
        [property: JsonPropertyName("number_of_pages_median")] int? NumberOfPagesMedian);
}
