using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Services.External;

public sealed class JikanMetadataProvider(
    [ServiceKey] string serviceKey,
    IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    private readonly string _mediaType = serviceKey.StartsWith("manga", StringComparison.OrdinalIgnoreCase) ? "manga" : "anime";

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Jikan");
        var endpoint = _mediaType == "manga"
            ? $"manga?q={Uri.EscapeDataString(query)}&limit=10"
            : $"anime?q={Uri.EscapeDataString(query)}&limit=10";

        try
        {
            var response = await client.GetFromJsonAsync<JikanSearchResponse>(endpoint, ct);
            if (response?.Data is null || response.Data.Count == 0)
            {
                return [];
            }

            return response.Data.Select(item => MapItem(item, _mediaType)).ToList();
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return [];
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Jikan");
        var endpoint = _mediaType == "manga"
            ? $"manga/{externalId}/full"
            : $"anime/{externalId}/full";

        try
        {
            var response = await client.GetFromJsonAsync<JikanDetailResponse>(endpoint, ct);
            if (response?.Data is null)
            {
                return null;
            }

            return MapItem(response.Data, _mediaType);
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

    private static ExternalMediaDto MapItem(JikanItem item, string type)
    {
        var primaryTitle = !string.IsNullOrWhiteSpace(item.TitleEnglish) ? item.TitleEnglish : item.Title;
        var originalTitle = !string.IsNullOrWhiteSpace(item.TitleJapanese) ? item.TitleJapanese : item.Title;
        var cover = item.Images?.Jpg?.LargeImageUrl ?? item.Images?.Webp?.LargeImageUrl ?? item.Images?.Jpg?.ImageUrl;
        var rating = item.Score;
        var votes = item.ScoredBy;

        var ratings = new List<ExternalRatingDto>();
        if (rating.HasValue && rating.Value > 0)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "MyAnimeList",
                Rating = Math.Round(rating.Value, 1),
                Votes = votes
            });
        }

        var studio = item.Studios?.FirstOrDefault()?.Name;
        var author = item.Authors?.FirstOrDefault()?.Name;
        var total = type == "manga" ? item.Chapters : item.Episodes;

        return new ExternalMediaDto
        {
            ExternalId = item.MalId.ToString(),
            Title = primaryTitle,
            OriginalTitle = originalTitle,
            CoverUrl = cover,
            Description = item.Synopsis,
            ReleaseYear = item.Year,
            Type = type,
            Studio = studio,
            Author = author,
            TotalCount = total,
            ExternalSource = "MyAnimeList",
            Rating = rating,
            RatingVotes = votes,
            Ratings = ratings.Count > 0 ? ratings : null
        };
    }

    private sealed class JikanSearchResponse
    {
        [JsonPropertyName("data")]
        public List<JikanItem>? Data { get; set; }
    }

    private sealed class JikanDetailResponse
    {
        [JsonPropertyName("data")]
        public JikanItem? Data { get; set; }
    }

    private sealed class JikanItem
    {
        [JsonPropertyName("mal_id")]
        public int MalId { get; set; }

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("title_english")]
        public string? TitleEnglish { get; set; }

        [JsonPropertyName("title_japanese")]
        public string? TitleJapanese { get; set; }

        [JsonPropertyName("synopsis")]
        public string? Synopsis { get; set; }

        [JsonPropertyName("images")]
        public JikanImages? Images { get; set; }

        [JsonPropertyName("year")]
        public int? Year { get; set; }

        [JsonPropertyName("episodes")]
        public int? Episodes { get; set; }

        [JsonPropertyName("chapters")]
        public int? Chapters { get; set; }

        [JsonPropertyName("score")]
        public double? Score { get; set; }

        [JsonPropertyName("scored_by")]
        public int? ScoredBy { get; set; }

        [JsonPropertyName("studios")]
        public List<JikanNamedItem>? Studios { get; set; }

        [JsonPropertyName("authors")]
        public List<JikanNamedItem>? Authors { get; set; }
    }

    private sealed class JikanImages
    {
        [JsonPropertyName("jpg")]
        public JikanImageUrls? Jpg { get; set; }

        [JsonPropertyName("webp")]
        public JikanImageUrls? Webp { get; set; }
    }

    private sealed class JikanImageUrls
    {
        [JsonPropertyName("image_url")]
        public string? ImageUrl { get; set; }

        [JsonPropertyName("large_image_url")]
        public string? LargeImageUrl { get; set; }
    }

    private sealed class JikanNamedItem
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }
    }
}
