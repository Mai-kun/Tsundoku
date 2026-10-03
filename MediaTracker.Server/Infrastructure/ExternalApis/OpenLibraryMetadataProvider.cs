using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class OpenLibraryMetadataProvider(IHttpClientFactory httpClientFactory) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "openlibrary",
        Name: "OpenLibrary",
        Description: "Books metadata & ratings provider",
        MediaTypes: ["book"],
        BaseAddress: "https://openlibrary.org/",
        IsDefault: true,
        Priority: 1);

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);

        try
        {
            var result = await client.GetFromJsonAsync<OpenLibraryResponse>(
                $"search.json?q={Uri.EscapeDataString(query)}&limit=10", ct);

            if (result?.Docs is not { Count: > 0 } docs)
            {
                return [];
            }

            return docs.ConvertAll(MapDoc);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var searchResults = await SearchAsync(title, ct);
        return searchResults.FirstOrDefault(d => d.ExternalId == externalId) ?? (searchResults.Count > 0 ? searchResults[0] : null);
    }

    private static ExternalMediaDto MapDoc(OpenLibraryDoc doc)
    {
        var rating = doc.RatingsAverage is { } ra && ra > 0 ? Math.Round(ra * 2.0, 1) : (double?)null;
        var ratings = rating is not null
            ? new List<ExternalRatingDto>
            {
                new() { Source = "OpenLibrary", Rating = rating.Value, Votes = doc.RatingsCount }
            }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = doc.Key ?? string.Empty,
            ExternalSource = "OpenLibrary",
            Title = doc.Title ?? string.Empty,
            CoverUrl = doc.CoverId is { } coverId
                ? $"https://covers.openlibrary.org/b/id/{coverId}-L.jpg"
                : null,
            ReleaseYear = doc.FirstPublishYear,
            Type = "book",
            Author = doc.AuthorName?.FirstOrDefault(),
            TotalCount = doc.NumberOfPagesMedian,
            Rating = rating,
            RatingVotes = doc.RatingsCount,
            Ratings = ratings
        };
    }

    private sealed record OpenLibraryResponse(List<OpenLibraryDoc>? Docs);

    private sealed record OpenLibraryDoc(
        string? Key,
        string? Title,
        [property: JsonPropertyName("author_name")] List<string>? AuthorName,
        [property: JsonPropertyName("cover_i")] int? CoverId,
        [property: JsonPropertyName("first_publish_year")] int? FirstPublishYear,
        [property: JsonPropertyName("number_of_pages_median")] int? NumberOfPagesMedian,
        [property: JsonPropertyName("ratings_average")] double? RatingsAverage,
        [property: JsonPropertyName("ratings_count")] int? RatingsCount);
}
