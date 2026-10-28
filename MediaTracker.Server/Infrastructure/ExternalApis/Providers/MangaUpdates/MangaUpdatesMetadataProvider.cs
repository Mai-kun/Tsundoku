using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

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
            Ratings = ratings.Count > 0 ? ratings : null,
            Genres = record.Genres is { Count: > 0 }
                ? record.Genres.Select(g => g.Genre).Where(g => !string.IsNullOrWhiteSpace(g)).Select(g => g!).Distinct(StringComparer.OrdinalIgnoreCase).ToList()
                : null
        };
    }
}
