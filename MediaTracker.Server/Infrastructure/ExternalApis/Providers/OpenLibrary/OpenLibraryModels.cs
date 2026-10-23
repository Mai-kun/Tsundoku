using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

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
