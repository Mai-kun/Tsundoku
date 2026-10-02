using System.Text.Json.Serialization;

namespace MediaTracker.Server.Services.External;

public sealed partial class JikanMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null,
    ILogger<JikanMetadataProvider>? logger = null) : IMetadataProvider
{
    public string Id => "jikan";
    public string Name => "MyAnimeList (Jikan)";
    public string Description => "Anime and Manga metadata & ratings provider";
    public IReadOnlyList<string> MediaTypes => ["anime", "manga"];

    private readonly string _mediaType = serviceKey?.StartsWith("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime";

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Jikan");
        var endpoint = _mediaType == "manga"
            ? $"manga?q={Uri.EscapeDataString(query)}&limit=10"
            : $"anime?q={Uri.EscapeDataString(query)}&limit=10";

        try
        {
            logger?.LogInformation("[Jikan] Requesting search: {BaseAddress}{Endpoint}", client.BaseAddress, endpoint);
            var response = await client.GetFromJsonAsync<JikanSearchResponse>(endpoint, ct);
            if (response?.Data is null || response.Data.Count == 0)
            {
                logger?.LogInformation("[Jikan] Search returned 0 results for '{Query}'", query);
                return [];
            }

            logger?.LogInformation("[Jikan] Search returned {Count} results for '{Query}'", response.Data.Count, query);
            return response.Data.ConvertAll(item => MapItem(item, _mediaType));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            logger?.LogWarning("[Jikan] Request canceled or timed out for search '{Query}' ({Endpoint})", query, endpoint);
            throw;
        }
        catch (Exception ex)
        {
            logger?.LogWarning(ex, "[Jikan] Search failed for '{Query}' ({Endpoint}): {Message}", query, endpoint, ex.Message);
            throw;
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
            logger?.LogInformation("[Jikan] Requesting details: {BaseAddress}{Endpoint}", client.BaseAddress, endpoint);
            var response = await client.GetFromJsonAsync<JikanDetailResponse>(endpoint, ct);
            if (response?.Data is null)
            {
                logger?.LogInformation("[Jikan] Details not found for ID {ExternalId}", externalId);
                return null;
            }

            logger?.LogInformation("[Jikan] Details fetched successfully for ID {ExternalId} ({Title})", externalId, title);
            return MapItem(response.Data, _mediaType);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            logger?.LogWarning("[Jikan] Details request canceled or timed out for ID {ExternalId}", externalId);
            throw;
        }
        catch (Exception ex)
        {
            logger?.LogWarning(ex, "[Jikan] Failed fetching details for ID {ExternalId}: {Message}", externalId, ex.Message);
            throw;
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
        if (rating is > 0)
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

        int? runtime = null;
        if (!string.IsNullOrWhiteSpace(item.Duration))
        {
            var match = DurationRegex().Match(item.Duration);
            if (match.Success && int.TryParse(match.Groups[1].Value, out var m)) runtime = m;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.MalId.ToString(),
            Title = primaryTitle,
            OriginalTitle = originalTitle,
            RomajiTitle = item.Title,
            CoverUrl = cover,
            Description = item.Synopsis,
            ReleaseYear = item.Year,
            ReleaseDate = item.Aired?.From,
            EndDate = item.Aired?.To,
            ReleaseStatus = item.Status,
            RuntimeMinutes = runtime,
            Type = type,
            Studio = studio,
            Author = author,
            TotalCount = total,
            Chapters = type == "manga" ? item.Chapters : null,
            Volumes = type == "manga" ? item.Volumes : null,
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

        [JsonPropertyName("volumes")]
        public int? Volumes { get; set; }

        [JsonPropertyName("score")]
        public double? Score { get; set; }

        [JsonPropertyName("scored_by")]
        public int? ScoredBy { get; set; }

        [JsonPropertyName("studios")]
        public List<JikanNamedItem>? Studios { get; set; }

        [JsonPropertyName("authors")]
        public List<JikanNamedItem>? Authors { get; set; }

        [JsonPropertyName("aired")]
        public JikanAired? Aired { get; set; }

        [JsonPropertyName("duration")]
        public string? Duration { get; set; }

        [JsonPropertyName("status")]
        public string? Status { get; set; }
    }

    private sealed class JikanAired
    {
        [JsonPropertyName("from")]
        public string? From { get; set; }

        [JsonPropertyName("to")]
        public string? To { get; set; }
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

    [System.Text.RegularExpressions.GeneratedRegex(@"^(\d+)\s*min")]
    private static partial System.Text.RegularExpressions.Regex DurationRegex();
}
