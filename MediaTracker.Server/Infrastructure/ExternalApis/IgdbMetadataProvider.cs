using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class IgdbMetadataProvider(
        IHttpClientFactory httpClientFactory,
        IOptions<ExternalApiOptions> options) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
            "igdb",
            "IGDB (Twitch)",
            "Internet Game Database by Twitch for video games",
            ["game"],
            "https://api.igdb.com/",
            true,
            Priority: 3,
            CanonicalName: "IGDB"
    );

    private string RawKey => options.Value.GetKey(Id) ?? string.Empty;

    private string? _cachedToken;
    private DateTime _tokenExpiry = DateTime.MinValue;

    private (string ClientId, string? ClientSecret) ParseKey()
    {
        var raw = RawKey.Trim();
        if (raw.Contains(':'))
        {
            var parts = raw.Split(':', 2);
            return (parts[0].Trim(), parts[1].Trim());
        }

        return (raw, null);
    }

    private async Task<string?> GetBearerTokenAsync(
            HttpClient client,
            string clientId,
            string? clientSecret,
            CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(clientSecret))
        {
            return _cachedToken;
        }

        if (!string.IsNullOrEmpty(_cachedToken) && DateTime.UtcNow < _tokenExpiry)
        {
            return _cachedToken;
        }

        try
        {
            using var oauthClient = httpClientFactory.CreateClient();
            var authUrl =
                    $"https://id.twitch.tv/oauth2/token?client_id={Uri.EscapeDataString(clientId)}&client_secret={Uri.EscapeDataString(clientSecret)}&grant_type=client_credentials";
            var resp = await oauthClient.PostAsync(authUrl, null, ct);
            if (!resp.IsSuccessStatusCode)
            {
                return null;
            }

            var body = await resp.Content.ReadFromJsonAsync<TwitchTokenResponse>(ct);
            if (body?.AccessToken is { Length: > 0 } token)
            {
                _cachedToken = token;
                _tokenExpiry = DateTime.UtcNow.AddSeconds(body.ExpiresIn > 60 ? body.ExpiresIn - 60 : 3600);
                return token;
            }
        }
        catch
        {
            // OAuth failure
        }

        return null;
    }

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var (clientId, clientSecret) = ParseKey();
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);
        var token = await GetBearerTokenAsync(client, clientId, clientSecret, ct);

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, "v4/games");
            req.Headers.Add("Client-ID", clientId);
            if (!string.IsNullOrEmpty(token))
            {
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            }

            var cleanQuery = query.Replace("\"", "\\\"");
            req.Content = new StringContent(
                    $"search \"{cleanQuery}\"; fields name,summary,cover.url,first_release_date,rating,total_rating,genres.name,status; limit 10;",
                    Encoding.UTF8,
                    "text/plain"
            );

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                return [];
            }

            var items = await resp.Content.ReadFromJsonAsync<List<IgdbGameItem>>(ct);
            if (items is null || items.Count == 0)
            {
                return [];
            }

            return items.ConvertAll(MapItem);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var results = await SearchAsync(!string.IsNullOrWhiteSpace(title) ? title : externalId, ct);
        return results.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
               ?? (results.Count > 0 ? results[0] : null);
    }

    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var (clientId, clientSecret) = ParseKey();
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return new ConnectionTestResult(false, 0, "Twitch Client-ID is required (format: ClientID:ClientSecret)");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            var token = await GetBearerTokenAsync(client, clientId, clientSecret, cts.Token);
            sw.Stop();
            if (!string.IsNullOrEmpty(token) || string.IsNullOrEmpty(clientSecret))
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            return new ConnectionTestResult(
                    false,
                    (int)sw.ElapsedMilliseconds,
                    "Twitch OAuth token authentication failed"
            );
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }

    private static ExternalMediaDto MapItem(IgdbGameItem item)
    {
        double? score = null;
        if (item.Rating is > 0)
        {
            score = Math.Round(item.Rating.Value / 10.0, 1);
        }
        else if (item.TotalRating is > 0)
        {
            score = Math.Round(item.TotalRating.Value / 10.0, 1);
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(
                    new ExternalRatingDto
                    {
                            Source = "IGDB",
                            Rating = score.Value,
                            Votes = null,
                    }
            );
        }

        var cover = item.Cover?.Url;
        if (!string.IsNullOrWhiteSpace(cover))
        {
            if (cover.StartsWith("//"))
            {
                cover = "https:" + cover;
            }

            cover = cover.Replace("t_thumb", "t_cover_big");
        }

        int? year = null;
        string? releaseDate = null;
        if (item.FirstReleaseDate.HasValue)
        {
            var dto = DateTimeOffset.FromUnixTimeSeconds(item.FirstReleaseDate.Value);
            year = dto.Year;
            releaseDate = dto.ToString("yyyy-MM-dd");
        }

        var genres = item.Genres?.Select(g => g.Name).Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n!).ToList();

        return new ExternalMediaDto
        {
                ExternalId = item.Id.ToString(),
                ExternalSource = "IGDB",
                Title = item.Name ?? "Unknown Game",
                CoverUrl = cover,
                Description = item.Summary,
                ReleaseYear = year,
                ReleaseDate = releaseDate,
                ReleaseStatus = DetermineStatus(item.FirstReleaseDate, item.Status),
                Genres = genres,
                Platform = "Multiplatform",
                Type = "game",
                Rating = score,
                Ratings = ratings,
        };
    }

    private static string DetermineStatus(long? firstReleaseDate, int? status)
    {
        if (firstReleaseDate.HasValue
            && DateTimeOffset.FromUnixTimeSeconds(firstReleaseDate.Value) > DateTimeOffset.UtcNow)
        {
            return "Coming Soon";
        }

        if (status == 4)
        {
            return "Early Access";
        }

        return "Full Release";
    }

    private sealed class TwitchTokenResponse
    {
        [JsonPropertyName("access_token")]
        public string? AccessToken { get; set; }

        [JsonPropertyName("expires_in")]
        public int ExpiresIn { get; set; }
    }

    private sealed class IgdbGameItem
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("summary")]
        public string? Summary { get; set; }

        [JsonPropertyName("first_release_date")]
        public long? FirstReleaseDate { get; set; }

        [JsonPropertyName("rating")]
        public double? Rating { get; set; }

        [JsonPropertyName("total_rating")]
        public double? TotalRating { get; set; }

        [JsonPropertyName("status")]
        public int? Status { get; set; }

        [JsonPropertyName("cover")]
        public IgdbCover? Cover { get; set; }

        [JsonPropertyName("genres")]
        public List<IgdbNamedItem>? Genres { get; set; }
    }

    private sealed class IgdbNamedItem
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }
    }

    private sealed class IgdbCover
    {
        [JsonPropertyName("url")]
        public string? Url { get; set; }
    }
}