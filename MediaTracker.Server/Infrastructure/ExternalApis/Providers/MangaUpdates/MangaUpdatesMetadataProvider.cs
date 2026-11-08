using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.MangaUpdates;

public sealed class MangaUpdatesMetadataProvider(
    IHttpClientFactory httpClientFactory) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "mangaupdates",
        Name: "MangaUpdates",
        Description: "Manga and Manhwa metadata & ratings provider",
        MediaTypes: ["manga"],
        BaseAddress: "https://api.mangaupdates.com/v1/",
        Priority: 4);

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var requestPayload = new MuSearchRequest(query, "title", 10);

        try
        {
            var res = await client.PostAsJsonAsync(
                "series/search", requestPayload, AppJsonSerializerContext.Default.MuSearchRequest, ct);
            if (!res.IsSuccessStatusCode)
            {
                return [];
            }

            var response = await res.Content.ReadFromJsonAsync(AppJsonSerializerContext.Default.MuSearchResponse, cancellationToken: ct);
            if (response?.Results is null || response.Results.Count == 0)
            {
                return [];
            }

            return [.. response.Results
                .Where(r => r.Record is not null)
                .Select(r => MapItem(r.Record!))];
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);

        try
        {
            var response = await client.GetFromJsonAsync($"series/{externalId}", AppJsonSerializerContext.Default.MuSeriesRecord, ct);
            if (response is null)
            {
                return null;
            }

            return MapItem(response);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    /// <summary>
    /// Related titles from the <c>related_series</c> array the details answer already carries — one
    /// request, no second lookup: MangaUpdates reports only the neighbour's id and name, and the
    /// Related tab renders a title row fine without a cover or score.
    ///
    /// <paramref name="externalId"/> is a MangaUpdates id only when the row was added from
    /// MangaUpdates; another source's id matches nothing, and the panel stays empty instead of
    /// guessing.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRelationDto>> GetRelationsAsync(
        string? externalId,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(externalId) || !long.TryParse(externalId, out _))
        {
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);

        try
        {
            var record = await client.GetFromJsonAsync(
                $"series/{externalId}", AppJsonSerializerContext.Default.MuSeriesRecord, ct);

            var relations = new List<ExternalRelationDto>();
            var seen = new HashSet<long>();
            foreach (var related in record?.RelatedSeries ?? [])
            {
                if (related is null
                    || related.RelatedSeriesId <= 0
                    || string.IsNullOrWhiteSpace(related.RelatedSeriesName)
                    || !seen.Add(related.RelatedSeriesId))
                {
                    continue;
                }

                relations.Add(new ExternalRelationDto(
                    MapRelationType(related.RelationType),
                    new ExternalMediaDto
                    {
                        ExternalId = related.RelatedSeriesId.ToString(System.Globalization.CultureInfo.InvariantCulture),
                        Title = related.RelatedSeriesName!,
                        Type = "manga",
                        ExternalSource = "MangaUpdates",
                    }));
            }

            return relations;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // A failed details call leaves the tab empty rather than erroring over decoration.
            return [];
        }
    }

    /// <summary>
    /// MangaUpdates' relation labels → the canonical keys the Related tab groups on. Their list
    /// spells them in prose ("Side story", "Alternative version"), so the mapping is a casefold
    /// rather than an exact match; anything unlisted reports as OTHER instead of being dropped.
    /// </summary>
    public static string MapRelationType(string? relationType) =>
        (relationType ?? string.Empty).Trim().ToLowerInvariant().Replace("_", " ") switch
        {
            "sequel" => "SEQUEL",
            "prequel" => "PREQUEL",
            "adaptation" or "adapted from" => "ADAPTATION",
            "side story" => "SIDE_STORY",
            "spin-off" or "spin off" => "SPIN_OFF",
            "alternative version" or "alternative" => "ALTERNATIVE",
            "character" => "CHARACTER",
            "summary" => "SUMMARY",
            _ => "OTHER",
        };

    /// <summary>MangaUpdates' origin label → the format buckets the UI shows. OEL (an English-language
    /// original) is the one verdict only this source reports; everything unknown stays plain manga.
    /// </summary>
    private static string? MapFormat(string? type) => (type ?? string.Empty).Trim().ToLowerInvariant() switch
    {
        "oel" => MangaFormats.Oel,
        "manhwa" => MangaFormats.Manhwa,
        "manhua" => MangaFormats.Manhua,
        _ => MangaFormats.Manga,
    };

    private static ExternalMediaDto MapItem(MuSeriesRecord record)
    {
        var cover = record.Image?.Url?.Original ?? record.Image?.Url?.Thumb;
        var author = record.Authors?.FirstOrDefault()?.Name;
        int? year = int.TryParse(record.Year, out var y) ? y : null;

        var ratingScore = record.Rating?.BayesianRating ?? record.Rating?.Rating ?? record.BayesianRating;
        var ratingVotes = record.Rating?.Votes ?? record.RatingVotes;
        var ratings = new List<ExternalRatingDto>();
        if (ratingScore is > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "MangaUpdates",
                Rating = Math.Round(ratingScore.Value, 1),
                Votes = ratingVotes
            });
        }

        return new ExternalMediaDto
        {
            ExternalId = record.SeriesId.ToString(),
            Title = record.Title,
            OriginalTitle = record.Associated?.FirstOrDefault()?.Title,
            CoverUrl = cover,
            Description = record.Description,
            ReleaseYear = year,
            Type = "manga",
            MangaFormat = MapFormat(record.Type),
            Author = author,
            TotalCount = record.LatestChapter,
            Chapters = record.LatestChapter,
            ExternalSource = "MangaUpdates",
            Rating = ratingScore is > 0 ? Math.Round(ratingScore.Value, 1) : null,
            RatingVotes = ratingVotes,
            Ratings = ratings.Count > 0 ? ratings : null,
            // Only the curated genre list belongs in the genres block; the user-voted categories are
            // a trope dump of dozens of rows that buried the 3–5 real genres under noise. At most
            // the top five ride along as Tags instead.
            Genres = record.Genres is { Count: > 0 }
                ? record.Genres.Select(g => g.Genre).Where(g => !string.IsNullOrWhiteSpace(g)).Select(g => g!).Distinct(StringComparer.OrdinalIgnoreCase).ToList()
                : null,
            Tags = record.Categories is { Count: > 0 }
                ? record.Categories
                    .Select(c => c.Category)
                    .Where(c => !string.IsNullOrWhiteSpace(c))
                    .Select(c => c!)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Take(5)
                    .ToList()
                : null
        };
    }
}
