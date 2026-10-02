using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class MangaUpdatesMetadataProvider(
    IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    public string Id => "mangaupdates";
    public string Name => "MangaUpdates";
    public string Description => "Manga and Manhwa metadata & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["manga"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("MangaUpdates");
        var requestPayload = new
        {
            search = query,
            stype = "title",
            perpage = 10
        };

        try
        {
            var res = await client.PostAsJsonAsync("series/search", requestPayload, ct);
            if (!res.IsSuccessStatusCode)
            {
                return [];
            }

            var response = await res.Content.ReadFromJsonAsync<MuSearchResponse>(cancellationToken: ct);
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

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("MangaUpdates");

        try
        {
            var response = await client.GetFromJsonAsync<MuSeriesRecord>($"series/{externalId}", ct);
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
            Author = author,
            TotalCount = record.LatestChapter,
            Chapters = record.LatestChapter,
            ExternalSource = "MangaUpdates",
            Rating = ratingScore is > 0 ? Math.Round(ratingScore.Value, 1) : null,
            RatingVotes = ratingVotes,
            Ratings = ratings.Count > 0 ? ratings : null
        };
    }

    private sealed class MuSearchResponse
    {
        [JsonPropertyName("results")]
        public List<MuSearchResult>? Results { get; set; }
    }

    private sealed class MuSearchResult
    {
        [JsonPropertyName("record")]
        public MuSeriesRecord? Record { get; set; }
    }

    private sealed class MuRating
    {
        [JsonPropertyName("bayesian_rating")]
        public double? BayesianRating { get; set; }

        [JsonPropertyName("rating")]
        public double? Rating { get; set; }

        [JsonPropertyName("votes")]
        public int? Votes { get; set; }
    }

    private sealed class MuSeriesRecord
    {
        [JsonPropertyName("series_id")]
        public long SeriesId { get; set; }

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        [JsonPropertyName("year")]
        public string? Year { get; set; }

        [JsonPropertyName("bayesian_rating")]
        public double? BayesianRating { get; set; }

        [JsonPropertyName("rating_votes")]
        public int? RatingVotes { get; set; }

        [JsonPropertyName("rating")]
        public MuRating? Rating { get; set; }

        [JsonPropertyName("latest_chapter")]
        public int? LatestChapter { get; set; }

        [JsonPropertyName("image")]
        public MuImage? Image { get; set; }

        [JsonPropertyName("authors")]
        public List<MuAuthor>? Authors { get; set; }

        [JsonPropertyName("associated")]
        public List<MuAssociatedTitle>? Associated { get; set; }
    }

    private sealed class MuImage
    {
        [JsonPropertyName("url")]
        public MuImageUrl? Url { get; set; }
    }

    private sealed class MuImageUrl
    {
        [JsonPropertyName("original")]
        public string? Original { get; set; }

        [JsonPropertyName("thumb")]
        public string? Thumb { get; set; }
    }

    private sealed class MuAuthor
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }
    }

    private sealed class MuAssociatedTitle
    {
        [JsonPropertyName("title")]
        public string? Title { get; set; }
    }
}
