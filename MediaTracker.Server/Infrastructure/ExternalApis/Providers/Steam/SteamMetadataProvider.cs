using System.Globalization;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class SteamMetadataProvider(IHttpClientFactory httpClientFactory) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "steam",
        Name: "Steam",
        Description: "PC games metadata, store reviews & achievements (API key optional — only needed for Steam profile library import)",
        MediaTypes: ["game"],
        BaseAddress: "https://store.steampowered.com/api/",
        RequiresApiKey: false,
        OptionalApiKey: true,
        Priority: 2);

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"storesearch/?term={Uri.EscapeDataString(query)}&l=english&cc=US";

        try
        {
            var res = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.SteamStoreSearchResponse, ct);
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

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"appdetails?appids={Uri.EscapeDataString(externalId)}&l=english";

        try
        {
            var dict = await client.GetFromJsonAsync(endpoint, AppJsonSerializerContext.Default.DictionaryStringSteamAppDetailsWrapper, ct);
            if (dict is null || !dict.TryGetValue(externalId, out var wrapper) || wrapper.Data is null || !wrapper.Success)
            {
                return null;
            }

            var dto = MapDetailsItem(externalId, wrapper.Data);

            try
            {
                using var reviewsCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                reviewsCts.CancelAfter(TimeSpan.FromSeconds(5));
                var reviewsRes = await client.GetFromJsonAsync($"https://store.steampowered.com/appreviews/{externalId}?json=1&purchase_type=all&language=all", AppJsonSerializerContext.Default.SteamReviewsResponse, reviewsCts.Token);

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

        var cover = item.Id > 0
            ? $"https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/{item.Id}/library_600x900.jpg"
            : item.TinyImage;

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Steam",
            SteamAppId = item.Id > 0 ? item.Id.ToString(CultureInfo.InvariantCulture) : null,
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

        var coverUrl = !string.IsNullOrWhiteSpace(externalId)
            ? $"https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/{externalId}/library_600x900.jpg"
            : data.HeaderImage;

        return new ExternalMediaDto
        {
            ExternalId = externalId,
            ExternalSource = "Steam",
            SteamAppId = externalId,
            Title = data.Name ?? "Unknown Game",
            CoverUrl = coverUrl,
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
}
