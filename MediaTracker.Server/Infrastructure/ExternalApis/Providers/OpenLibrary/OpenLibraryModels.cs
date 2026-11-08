using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.OpenLibrary;

internal sealed record OpenLibraryResponse(List<OpenLibraryDoc>? Docs);

internal sealed record OpenLibraryDoc(
    string? Key,
    string? Title,
    [property: JsonPropertyName("author_name")] List<string>? AuthorName,
    [property: JsonPropertyName("cover_i")] int? CoverId,
    [property: JsonPropertyName("first_publish_year")] int? FirstPublishYear,
    [property: JsonPropertyName("subtitle")] string? Subtitle,
    [property: JsonPropertyName("subject")] List<string>? Subject,
    [property: JsonPropertyName("number_of_pages_median")] int? NumberOfPagesMedian,
    [property: JsonPropertyName("number_of_pages")] List<int>? NumberOfPages,
    [property: JsonPropertyName("ratings_average")] double? RatingsAverage,
    [property: JsonPropertyName("ratings_count")] int? RatingsCount);

/// <summary>
/// Edition answer of <c>openlibrary.org/books/{id}.json</c>. Only the work reference is read:
/// an edition id is resolved to its work so the search index (which indexes works, not editions)
/// can be queried by key.
/// </summary>
internal sealed class OpenLibraryEdition
{
    [JsonPropertyName("works")]
    public List<OpenLibraryWorkRef>? Works { get; set; }
}

internal sealed class OpenLibraryWorkRef
{
    [JsonPropertyName("key")]
    public string? Key { get; set; }
}
