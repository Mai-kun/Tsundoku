using System.Diagnostics;
using System.Text.RegularExpressions;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.OpenLibrary;

public sealed class OpenLibraryMetadataProvider(
    IHttpClientFactory httpClientFactory,
    ILogger<OpenLibraryMetadataProvider>? logger = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "openlibrary",
        Name: "OpenLibrary",
        Description: "Books metadata & ratings provider",
        MediaTypes: ["book"],
        BaseAddress: "https://openlibrary.org/",
        IsDefault: true,
        Priority: 1);

    private const string SearchFields =
        "key,title,author_name,cover_i,first_publish_year,number_of_pages_median,"
        + "number_of_pages,subtitle,ratings_average,ratings_count,subject,publisher,physical_format,isbn";

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);

        var isbnCandidate = IsbnCandidateOf(query);
        var endpoint = IsIsbn(isbnCandidate)
            ? $"search.json?isbn={Uri.EscapeDataString(isbnCandidate)}&limit=10&fields={SearchFields}"
            : $"search.json?q={Uri.EscapeDataString(query)}&limit=10&fields={SearchFields}";

        try
        {
            ExternalApiLog.Querying(logger, Name, "book", query);
            var sw = Stopwatch.StartNew();
            var result = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.OpenLibraryResponse, ct);

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

    /// <summary>ISBN-10 (digits + optional check X) or ISBN-13 (13 digits), separators already stripped.</summary>
    private static bool IsIsbn(string value) =>
        Regex.IsMatch(value, """^(?:\d{9}[\dxX]|\d{13})$""");

    /// <summary>The query with hyphens, spaces and an optional "isbn:" prefix stripped away.</summary>
    private static string IsbnCandidateOf(string query)
    {
        var cleaned = Regex.Replace(query.Trim(), @"[\s\-]", "");
        return cleaned.StartsWith("isbn:", StringComparison.OrdinalIgnoreCase) ? cleaned[5..] : cleaned;
    }

    /// <summary>A "works by author" query: OpenLibrary's own <c>author</c> index instead of a title match.</summary>
    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchByCreatorAsync(string creator, CancellationToken ct)
    {
        var clean = creator.Trim();
        if (clean.Length == 0) return [];

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"search.json?author={Uri.EscapeDataString(clean)}&limit=10&fields={SearchFields}";

        try
        {
            ExternalApiLog.Querying(logger, Name, "book author", clean);
            var sw = Stopwatch.StartNew();
            var result = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.OpenLibraryResponse, ct);

            var mapped = result?.Docs is { Count: > 0 } docs ? docs.ConvertAll(MapDoc) : [];
            ExternalApiLog.Returned(logger, Name, mapped.Count, sw.ElapsedMilliseconds);
            if (mapped.Count > 0) return mapped;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            ExternalApiLog.Failed(logger, Name, ex, client.BaseAddress + endpoint);
        }

        return await base.SearchByCreatorAsync(clean, ct);
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        ExternalMediaDto? baseDto = null;
        string? workKey = null;

        var cleanId = (externalId ?? string.Empty).Trim();
        var isbn = IsbnCandidateOf(cleanId);

        if (IsIsbn(isbn))
        {
            var edition = await FetchEditionByIsbnAsync(isbn, ct);
            if (edition is not null)
            {
                workKey = edition.Works?.FirstOrDefault(w => !string.IsNullOrWhiteSpace(w.Key))?.Key;
                baseDto = MapEdition(edition, isbn);
            }

            var byIsbn = await SearchByExactQueryAsync($"isbn={Uri.EscapeDataString(isbn)}", ct);
            if (byIsbn is { Count: > 0 })
            {
                baseDto = baseDto is not null ? MergeSearchResults(baseDto, byIsbn[0]) : byIsbn[0];
                workKey ??= byIsbn[0].ExternalId;
            }
        }
        else if (cleanId.StartsWith("OL", StringComparison.OrdinalIgnoreCase)
                 || cleanId.StartsWith("/works/OL", StringComparison.OrdinalIgnoreCase)
                 || cleanId.StartsWith("/books/OL", StringComparison.OrdinalIgnoreCase))
        {
            var rawId = cleanId.TrimStart('/');
            if (rawId.StartsWith("works/", StringComparison.OrdinalIgnoreCase))
            {
                workKey = "/" + rawId;
            }
            else if (rawId.StartsWith("books/", StringComparison.OrdinalIgnoreCase) || !cleanId.EndsWith("W", StringComparison.OrdinalIgnoreCase))
            {
                var editionId = rawId.StartsWith("books/", StringComparison.OrdinalIgnoreCase) ? rawId[6..] : rawId;
                var edition = await FetchEditionAsync(editionId, ct);
                if (edition is not null)
                {
                    workKey = edition.Works?.FirstOrDefault(w => !string.IsNullOrWhiteSpace(w.Key))?.Key;
                    baseDto = MapEdition(edition, ExtractIsbn(edition.Isbn13, edition.Isbn10));
                }
            }
            else
            {
                workKey = $"/works/{cleanId}";
            }
        }

        if (baseDto is null && !string.IsNullOrWhiteSpace(workKey))
        {
            var byKey = await SearchByExactQueryAsync($"q={Uri.EscapeDataString($"key:{workKey}")}", ct);
            if (byKey is { Count: > 0 })
            {
                baseDto = byKey[0];
            }
        }

        if (baseDto is null)
        {
            var searchResults = await SearchAsync(title, ct);
            baseDto = searchResults.FirstOrDefault(d => d.ExternalId == externalId) ?? (searchResults.Count > 0 ? searchResults[0] : null);
            if (baseDto is not null && string.IsNullOrWhiteSpace(workKey))
            {
                workKey = baseDto.ExternalId;
            }
        }

        if (baseDto is null)
        {
            return null;
        }

        // Enrich with Work details: description, alternative covers, canonical genres from subjects
        if (!string.IsNullOrWhiteSpace(workKey))
        {
            var work = await FetchWorkAsync(workKey, ct);
            if (work is not null)
            {
                baseDto = MergeWorkDetails(baseDto, work);
            }
        }

        return baseDto;
    }

    private async Task<IReadOnlyList<ExternalMediaDto>?> SearchByExactQueryAsync(string queryParameter, CancellationToken ct)
    {
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            var result = await client.GetFromJsonAsync(
                $"search.json?{queryParameter}&limit=10&fields={SearchFields}",
                AppJsonSerializerContext.Default.OpenLibraryResponse, ct);
            return result?.Docs is { Count: > 0 } docs ? docs.ConvertAll(MapDoc) : null;
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

    private async Task<OpenLibraryEdition?> FetchEditionByIsbnAsync(string isbn, CancellationToken ct)
    {
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            return await client.GetFromJsonAsync(
                $"isbn/{Uri.EscapeDataString(isbn)}.json",
                AppJsonSerializerContext.Default.OpenLibraryEdition, ct);
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

    private async Task<OpenLibraryEdition?> FetchEditionAsync(string editionId, CancellationToken ct)
    {
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            return await client.GetFromJsonAsync(
                $"books/{Uri.EscapeDataString(editionId)}.json",
                AppJsonSerializerContext.Default.OpenLibraryEdition, ct);
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

    private async Task<OpenLibraryWork?> FetchWorkAsync(string workKey, CancellationToken ct)
    {
        try
        {
            var cleanKey = workKey.TrimStart('/');
            var client = httpClientFactory.CreateClient(Id);
            return await client.GetFromJsonAsync(
                $"{cleanKey}.json",
                AppJsonSerializerContext.Default.OpenLibraryWork, ct);
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

    private static ExternalMediaDto MapDoc(OpenLibraryDoc doc)
    {
        var rating = doc.RatingsAverage is { } ra and > 0 ? Math.Round(ra * 2.0, 1) : (double?)null;
        var ratings = rating is not null
            ? new List<ExternalRatingDto>
            {
                new() { Source = "OpenLibrary", Rating = rating.Value, Votes = doc.RatingsCount }
            }
            : null;

        var firstPublisher = doc.Publisher?.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p))?.Trim();
        var format = MapPhysicalFormat(doc.PhysicalFormat);
        var isbn = ExtractIsbn(doc.Isbn);
        var genres = NormalizeSubjects(doc.Subject);
        var coverUrl = doc.CoverId is { } coverId and > 0
            ? $"https://covers.openlibrary.org/b/id/{coverId}-L.jpg"
            : null;

        return new ExternalMediaDto
        {
            ExternalId = doc.Key ?? string.Empty,
            ExternalSource = "OpenLibrary",
            Title = doc.Title ?? string.Empty,
            CoverUrl = coverUrl,
            Description = doc.Subtitle,
            ReleaseYear = doc.FirstPublishYear,
            Type = "book",
            Author = doc.AuthorName?.FirstOrDefault(),
            TotalCount = doc.NumberOfPagesMedian ?? doc.NumberOfPages?.FirstOrDefault(p => p > 0),
            Rating = rating,
            RatingVotes = doc.RatingsCount,
            Ratings = ratings,
            Genres = genres,
            Studio = firstPublisher,
            Format = format,
            Isbn = isbn,
            Covers = coverUrl is not null ? [coverUrl] : null,
        };
    }

    private static ExternalMediaDto MapEdition(OpenLibraryEdition edition, string? fallbackIsbn)
    {
        var isbn = ExtractIsbn(edition.Isbn13, edition.Isbn10) ?? fallbackIsbn;
        var firstPublisher = edition.Publishers?.FirstOrDefault(p => !string.IsNullOrWhiteSpace(p))?.Trim();
        var format = MapPhysicalFormat(edition.PhysicalFormat);
        var altCovers = (edition.Covers ?? [])
            .Where(c => c > 0)
            .Distinct()
            .Take(10)
            .Select(c => $"https://covers.openlibrary.org/b/id/{c}-L.jpg")
            .ToList();
        var coverUrl = altCovers.Count > 0 ? altCovers[0] : null;

        return new ExternalMediaDto
        {
            ExternalId = edition.Works?.FirstOrDefault()?.Key ?? isbn ?? string.Empty,
            ExternalSource = "OpenLibrary",
            Title = edition.Title ?? string.Empty,
            CoverUrl = coverUrl,
            Description = edition.Description,
            Type = "book",
            TotalCount = edition.NumberOfPages,
            Studio = firstPublisher,
            Format = format,
            Isbn = isbn,
            Covers = altCovers.Count > 0 ? altCovers : null,
        };
    }

    private static ExternalMediaDto MergeSearchResults(ExternalMediaDto primary, ExternalMediaDto searchDoc)
    {
        return primary with
        {
            ExternalId = !string.IsNullOrWhiteSpace(searchDoc.ExternalId) ? searchDoc.ExternalId : primary.ExternalId,
            Author = primary.Author ?? searchDoc.Author,
            ReleaseYear = primary.ReleaseYear ?? searchDoc.ReleaseYear,
            Rating = searchDoc.Rating ?? primary.Rating,
            RatingVotes = searchDoc.RatingVotes ?? primary.RatingVotes,
            Ratings = searchDoc.Ratings ?? primary.Ratings,
            TotalCount = primary.TotalCount ?? searchDoc.TotalCount,
            Studio = primary.Studio ?? searchDoc.Studio,
            Format = primary.Format ?? searchDoc.Format,
            Isbn = primary.Isbn ?? searchDoc.Isbn,
            Genres = primary.Genres is { Count: > 0 } ? primary.Genres : searchDoc.Genres,
            CoverUrl = primary.CoverUrl ?? searchDoc.CoverUrl,
            Covers = primary.Covers is { Count: > 0 }
                ? (searchDoc.Covers is { Count: > 0 } ? primary.Covers.Concat(searchDoc.Covers).Distinct().ToList() : primary.Covers)
                : searchDoc.Covers,
        };
    }

    private static ExternalMediaDto MergeWorkDetails(ExternalMediaDto dto, OpenLibraryWork work)
    {
        var desc = !string.IsNullOrWhiteSpace(work.Description) ? work.Description.Trim() : dto.Description;
        var genres = NormalizeSubjects(work.Subjects) ?? dto.Genres;
        var altCovers = (work.Covers ?? [])
            .Where(c => c > 0)
            .Distinct()
            .Take(10)
            .Select(c => $"https://covers.openlibrary.org/b/id/{c}-L.jpg")
            .ToList();

        var covers = dto.Covers is { Count: > 0 }
            ? dto.Covers.Concat(altCovers).Distinct().ToList()
            : (altCovers.Count > 0 ? altCovers : null);

        return dto with
        {
            Description = desc,
            Genres = genres,
            Covers = covers,
            CoverUrl = dto.CoverUrl ?? (covers is { Count: > 0 } ? covers[0] : null)
        };
    }

    internal static string? MapPhysicalFormat(string? physicalFormat)
    {
        if (string.IsNullOrWhiteSpace(physicalFormat)) return null;
        var lower = physicalFormat.Trim().ToLowerInvariant();
        if (lower.Contains("paperback") || lower.Contains("pocket") || lower.Contains("softcover") || lower.Contains("мягк"))
            return "Мягкая обложка";
        if (lower.Contains("hardcover") || lower.Contains("hardback") || lower.Contains("тверд") || lower.Contains("твёрд"))
            return "Твёрдый переплёт";
        if (lower.Contains("ebook") || lower.Contains("electronic") || lower.Contains("электрон"))
            return "Электронная книга";
        if (lower.Contains("audio") || lower.Contains("аудио"))
            return "Аудиокнига";
        return physicalFormat.Trim();
    }

    internal static string? ExtractIsbn(List<string>? isbns, List<string>? isbns10 = null)
    {
        if (isbns is { Count: > 0 })
        {
            var isbn13 = isbns.FirstOrDefault(i => !string.IsNullOrWhiteSpace(i) && Regex.Replace(i, @"[\s\-]", "").Length == 13);
            if (isbn13 is not null) return isbn13.Trim();
            var isbn10 = isbns.FirstOrDefault(i => !string.IsNullOrWhiteSpace(i) && Regex.Replace(i, @"[\s\-]", "").Length == 10);
            if (isbn10 is not null) return isbn10.Trim();
            var any = isbns.FirstOrDefault(i => !string.IsNullOrWhiteSpace(i));
            if (any is not null) return any.Trim();
        }
        if (isbns10 is { Count: > 0 })
        {
            var first10 = isbns10.FirstOrDefault(i => !string.IsNullOrWhiteSpace(i));
            if (first10 is not null) return first10.Trim();
        }
        return null;
    }

    internal static List<string>? NormalizeSubjects(List<string>? subjects)
    {
        if (subjects is not { Count: > 0 }) return null;
        var list = new List<string>();
        foreach (var sub in subjects)
        {
            if (string.IsNullOrWhiteSpace(sub)) continue;
            if (GenreNormalizer.IsPrimaryGenre(sub))
            {
                var normalized = GenreNormalizer.ToRussian(sub);
                if (!string.IsNullOrWhiteSpace(normalized) && !list.Contains(normalized, StringComparer.OrdinalIgnoreCase))
                {
                    list.Add(normalized);
                }
            }
        }
        return list.Count > 0 ? list : null;
    }
}
