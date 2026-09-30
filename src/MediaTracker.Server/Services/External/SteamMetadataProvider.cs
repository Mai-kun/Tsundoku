using System.Globalization;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Services.External;

public sealed class SteamMetadataProvider(IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    public string Id => "steam";
    public string Name => "Steam";
    public string Description => "PC games metadata and Steam Community reviews provider";
    public IReadOnlyList<string> MediaTypes => ["game"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Steam");
        var endpoint = $"storesearch/?term={Uri.EscapeDataString(query)}&l=english&cc=US";

        try
        {
            var res = await client.GetFromJsonAsync<SteamStoreSearchResponse>(endpoint, ct);
            if (res?.Items is null || res.Items.Count == 0)
            {
                return [];
            }

            return res.Items.ConvertAll(MapSearchItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient("Steam");
        var endpoint = $"appdetails?appids={Uri.EscapeDataString(externalId)}&l=english";

        try
        {
            var dict = await client.GetFromJsonAsync<Dictionary<string, SteamAppDetailsWrapper>>(endpoint, ct);
            if (dict is null || !dict.TryGetValue(externalId, out var wrapper) || wrapper.Data is null || !wrapper.Success)
            {
                return null;
            }

            var dto = MapDetailsItem(externalId, wrapper.Data);

            try
            {
                using var reviewsCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                reviewsCts.CancelAfter(TimeSpan.FromSeconds(5));
                var reviewsRes = await client.GetFromJsonAsync<SteamReviewsResponse>(
                    $"https://store.steampowered.com/appreviews/{externalId}?json=1&purchase_type=all&language=all", reviewsCts.Token);

                if (reviewsRes?.QuerySummary is { TotalReviews: > 0 } summary)
                {
                    var rating = Math.Round((double)summary.TotalPositive / summary.TotalReviews * 10.0, 1);
                    var ratings = new List<ExternalRatingDto>
                    {
                        new()
                        {
                            Source = "Steam",
                            Rating = rating,
                            Votes = summary.TotalReviews
                        }
                    };
                    dto = dto with
                    {
                        Rating = rating,
                        RatingVotes = summary.TotalReviews,
                        Ratings = ratings
                    };
                }
            }
            catch
            {
                // reviews are optional enrichment
            }

            return dto;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    private static ExternalMediaDto MapSearchItem(SteamSearchItem item)
    {
        double? score = null;
        if (!string.IsNullOrWhiteSpace(item.Metascore) && double.TryParse(item.Metascore, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) && parsed > 0)
        {
            score = Math.Round(parsed / 10.0, 1);
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Steam",
                Rating = score.Value,
                Votes = null
            });
        }

        var cover = item.TinyImage;
        if (!string.IsNullOrWhiteSpace(cover) && cover.Contains("capsule_231x87"))
        {
            cover = $"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{item.Id}/header.jpg";
        }

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Steam",
            Title = item.Name,
            CoverUrl = cover,
            Platform = "PC",
            Type = "game",
            Rating = score,
            Ratings = ratings
        };
    }

    private static ExternalMediaDto MapDetailsItem(string externalId, SteamAppDetails data)
    {
        double? score = null;
        if (data.Metacritic?.Score is > 0)
        {
            score = Math.Round(data.Metacritic.Score.Value / 10.0, 1);
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Steam",
                Rating = score.Value,
                Votes = null
            });
        }

        int? releaseYear = null;
        string? formattedDate = null;
        if (!string.IsNullOrWhiteSpace(data.ReleaseDate?.Date))
        {
            var raw = data.ReleaseDate.Date.Trim();
            if (DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.None, out var relDate) ||
                DateTime.TryParse(raw, CultureInfo.CurrentCulture, DateTimeStyles.None, out relDate) ||
                DateTime.TryParse(raw, out relDate))
            {
                releaseYear = relDate.Year;
                formattedDate = relDate.ToString("yyyy-MM-dd");
            }
            else if (raw.Length >= 4 && int.TryParse(raw[..4], out var yr))
            {
                releaseYear = yr;
                formattedDate = $"{yr}-01-01";
            }
        }

        var studio = data.Developers is { Count: > 0 } ? string.Join(", ", data.Developers) : null;
        var genres = data.Genres?.Select(g => g.Description).Where(d => !string.IsNullOrWhiteSpace(d)).Select(d => d!).ToList();

        return new ExternalMediaDto
        {
            ExternalId = externalId,
            ExternalSource = "Steam",
            Title = data.Name ?? "Unknown Game",
            CoverUrl = data.HeaderImage,
            Description = !string.IsNullOrWhiteSpace(data.ShortDescription) ? data.ShortDescription : data.DetailedDescription,
            ReleaseDate = formattedDate,
            ReleaseYear = releaseYear,
            ReleaseStatus = DetermineStatus(data.ReleaseDate, data.Genres),
            Genres = genres,
            Studio = studio,
            Platform = "PC",
            Type = "game",
            Rating = score,
            Ratings = ratings
        };
    }

    private static string DetermineStatus(SteamReleaseDate? releaseDate, List<SteamGenre>? genres)
    {
        if (releaseDate?.ComingSoon == true) return "Coming Soon";
        if (!string.IsNullOrWhiteSpace(releaseDate?.Date) && DateTime.TryParse(releaseDate.Date, out var dt) && dt > DateTime.UtcNow)
            return "Coming Soon";
        if (genres?.Any(g => g.Id == "73" || g.Description?.Contains("Early Access", StringComparison.OrdinalIgnoreCase) == true) == true)
            return "Early Access";
        return "Full Release";
    }

    private sealed class SteamStoreSearchResponse
    {
        [JsonPropertyName("items")]
        public List<SteamSearchItem>? Items { get; set; }
    }

    private sealed class SteamSearchItem
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("tiny_image")]
        public string? TinyImage { get; set; }

        [JsonPropertyName("metascore")]
        public string? Metascore { get; set; }
    }

    private sealed class SteamAppDetailsWrapper
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("data")]
        public SteamAppDetails? Data { get; set; }
    }

    private sealed class SteamAppDetails
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("short_description")]
        public string? ShortDescription { get; set; }

        [JsonPropertyName("detailed_description")]
        public string? DetailedDescription { get; set; }

        [JsonPropertyName("header_image")]
        public string? HeaderImage { get; set; }

        [JsonPropertyName("developers")]
        public List<string>? Developers { get; set; }

        [JsonPropertyName("release_date")]
        public SteamReleaseDate? ReleaseDate { get; set; }

        [JsonPropertyName("genres")]
        public List<SteamGenre>? Genres { get; set; }

        [JsonPropertyName("metacritic")]
        public SteamMetacritic? Metacritic { get; set; }
    }

    private sealed class SteamGenre
    {
        [JsonPropertyName("id")]
        public string? Id { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }
    }

    private sealed class SteamReleaseDate
    {
        [JsonPropertyName("date")]
        public string? Date { get; set; }

        [JsonPropertyName("coming_soon")]
        public bool ComingSoon { get; set; }
    }

    private sealed class SteamMetacritic
    {
        [JsonPropertyName("score")]
        public double? Score { get; set; }
    }

    private sealed class SteamReviewsResponse
    {
        [JsonPropertyName("query_summary")]
        public SteamReviewSummary? QuerySummary { get; set; }
    }

    private sealed class SteamReviewSummary
    {
        [JsonPropertyName("total_reviews")]
        public int TotalReviews { get; set; }

        [JsonPropertyName("total_positive")]
        public int TotalPositive { get; set; }
    }
}
