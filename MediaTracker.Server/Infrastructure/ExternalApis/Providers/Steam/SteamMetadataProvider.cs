using System.Globalization;
using System.Text.RegularExpressions;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Steam;

public sealed class SteamMetadataProvider(IHttpClientFactory httpClientFactory) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "steam",
        Name: "Steam",
        Description: "PC games metadata & achievements. The Steam Web API key enables the full achievement database and syncing the player's unlocked achievements by SteamID64",
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
        var endpoint = $"appdetails?appids={Uri.EscapeDataString(externalId)}&l=russian&cc=US";

        try
        {
            // Age-gate: the store answers success:false for adult titles (and regional-locked ones)
            // unless the request carries an adult-profile cookie. This is our own client asking for
            // metadata the user already sees in the store, so the confirmation is the user's own.
            using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
            request.Headers.TryAddWithoutValidation("Cookie", "birthtime=283996801; mature_content=1;");
            using var resp = await client.SendAsync(request, ct);
            resp.EnsureSuccessStatusCode();

            var dict = await resp.Content.ReadFromJsonAsync(AppJsonSerializerContext.Default.DictionaryStringSteamAppDetailsWrapper, ct);
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
            // l=russian answers "9 сентября 2023 г.", so the Russian culture parse runs alongside
            // the invariant one; the bare-year regex is the last resort for formats neither parses.
            if (DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.None, out var relDate) ||
                DateTime.TryParse(raw, CultureInfo.GetCultureInfo("ru-RU"), DateTimeStyles.None, out relDate) ||
                DateTime.TryParse(raw, CultureInfo.CurrentCulture, DateTimeStyles.None, out relDate) ||
                DateTime.TryParse(raw, out relDate))
            {
                releaseYear = relDate.Year;
                formattedDate = relDate.ToString("yyyy-MM-dd");
            }
            else
            {
                var yearMatch = Regex.Match(raw, """\d{4}""");
                if (yearMatch.Success && int.TryParse(yearMatch.Value, out var yr))
                {
                    releaseYear = yr;
                    formattedDate = $"{yr}-01-01";
                }
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
