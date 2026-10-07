using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class OpenLibraryMetadataProvider(
    IHttpClientFactory httpClientFactory,
    ILogger<OpenLibraryMetadataProvider>? logger = null) : MetadataProviderBase
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

        // The bare search endpoint answers with a fixed, minimal field set that has no
        // description and no page count, so both rows of the book detail stayed empty and
        // "Страниц" rendered as 0. Asking for the fields explicitly is what fixes that; no
        // second request per book is needed.
        const string fields =
            "key,title,author_name,cover_i,first_publish_year,number_of_pages_median,"
            + "number_of_pages,subtitle,ratings_average,ratings_count,subject";

        var endpoint = $"search.json?q={Uri.EscapeDataString(query)}&limit=10&fields={fields}";

        try
        {
            ExternalApiLog.Querying(logger, Name, "book", query);
            var sw = Stopwatch.StartNew();
            var result = await client.GetFromJsonAsync<OpenLibraryResponse>(endpoint, ct);

            if (result?.Docs is not { Count: > 0 } docs)
            {
                ExternalApiLog.Returned(logger, Name, 0, sw.ElapsedMilliseconds);
                return [];
            }

            var mapped = docs.ConvertAll(MapDoc);

            ExternalApiLog.Returned(logger, Name, mapped.Count, sw.ElapsedMilliseconds);
            return mapped;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (HttpRequestException ex)
        {
            ExternalApiLog.Failed(logger, Name, ex, client.BaseAddress + endpoint);
            return [];
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
            // Search results only carry a `subject` list, so the synopsis is the best this endpoint
            // offers; Google Books is the richer fallback and the aggregator merges it in.
            Description = BuildDescription(doc.Subject, doc.Subtitle),
            ReleaseYear = doc.FirstPublishYear,
            Type = "book",
            Author = doc.AuthorName?.FirstOrDefault(),
            // number_of_pages is a per-edition list, number_of_pages_median the agreed value. The search index
            // publishes the median exactly when some edition carries a page count, so a work without
            // one has nothing to resolve: its editions genuinely carry no length. Both are read anyway
            // because a single doc can carry one without the other.
            TotalCount = doc.NumberOfPagesMedian ?? doc.NumberOfPages?.FirstOrDefault(p => p > 0),
            Rating = rating,
            RatingVotes = doc.RatingsCount,
            Ratings = ratings,
            Genres = doc.Subject is { Count: > 0 }
                ? doc.Subject.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase).Take(5).ToList()
                : null
        };
    }

    /// <summary>Joins the subject tags into one readable line, skipping empty entries.</summary>
    private static string? BuildDescription(List<string>? subjects, string? subtitle)
    {
        var parts = (subjects ?? [])
            .Where(subject => !string.IsNullOrWhiteSpace(subject))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(12);

        var tags = string.Join(", ", parts);
        if (string.IsNullOrWhiteSpace(subtitle) || string.IsNullOrWhiteSpace(tags))
        {
            return string.IsNullOrWhiteSpace(subtitle) ? NullIfBlank(tags) : subtitle;
        }

        return $"{subtitle}. {tags}";
    }

    private static string? NullIfBlank(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    private sealed record OpenLibraryResponse(List<OpenLibraryDoc>? Docs);

    private sealed record OpenLibraryDoc(
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
}
