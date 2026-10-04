using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class TvdbMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "thetvdb",
        Name: "TheTVDB",
        Description: "Community-driven database for TV shows and movies",
        MediaTypes: ["tvshow", "movie"],
        BaseAddress: "https://api4.thetvdb.com/",
        RequiresApiKey: true,
        Priority: 5,
        Aliases: ["tvdb"]);

    private readonly string _mediaType = serviceKey?.StartsWith("movie", StringComparison.OrdinalIgnoreCase) is true ? "movie" : "tvshow";
    private string ApiKey => options.Value.GetKey(Id) ?? options.Value.GetKey("tvdb") ?? string.Empty;

    private string? _cachedToken;
    private DateTime _tokenExpiry = DateTime.MinValue;

    private async Task<string?> GetTokenAsync(HttpClient client, string key, CancellationToken ct)
    {
        if (!string.IsNullOrEmpty(_cachedToken) && DateTime.UtcNow < _tokenExpiry)
        {
            return _cachedToken;
        }

        try
        {
            var res = await client.PostAsJsonAsync("v4/login", new { apikey = key }, ct);
            if (!res.IsSuccessStatusCode) return null;

            var body = await res.Content.ReadFromJsonAsync<TvdbLoginResponse>(ct);
            if (body?.Data?.Token is { Length: > 0 } token)
            {
                _cachedToken = token;
                _tokenExpiry = DateTime.UtcNow.AddHours(20);
                return token;
            }
        }
        catch
        {
            // login failed
        }

        return null;
    }

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key)) return [];

        var client = httpClientFactory.CreateClient(Id);
        var token = await GetTokenAsync(client, key, ct);
        if (string.IsNullOrEmpty(token)) return [];

        var typeParam = _mediaType == "movie" ? "movie" : "series";
        var endpoint = $"v4/search?query={Uri.EscapeDataString(query)}&type={typeParam}&limit=10";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode) return [];

            var body = await resp.Content.ReadFromJsonAsync<TvdbSearchResponse>(ct);
            if (body?.Data is null || body.Data.Count == 0) return [];

            return body.Data.ConvertAll(d => MapItem(d, _mediaType));
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
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return new ConnectionTestResult(false, 0, "API key is required");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            var token = await GetTokenAsync(client, key, cts.Token);
            sw.Stop();
            if (!string.IsNullOrEmpty(token))
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Authentication failed with provided API key");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }

    private static ExternalMediaDto MapItem(TvdbSearchItem item, string type)
    {
        int? year = null;
        if (!string.IsNullOrWhiteSpace(item.Year) && int.TryParse(item.Year, out var y))
        {
            year = y;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.TvdbId ?? item.ObjectId ?? item.Name ?? "unknown",
            ExternalSource = "TheTVDB",
            Title = item.Name ?? "Unknown",
            CoverUrl = item.ImageUrl,
            Description = item.Overview,
            ReleaseYear = year,
            Type = type,
            Ratings = []
        };
    }

    private sealed class TvdbLoginResponse
    {
        [JsonPropertyName("data")]
        public TvdbTokenData? Data { get; set; }
    }

    private sealed class TvdbTokenData
    {
        [JsonPropertyName("token")]
        public string? Token { get; set; }
    }

    private sealed class TvdbSearchResponse
    {
        [JsonPropertyName("data")]
        public List<TvdbSearchItem>? Data { get; set; }
    }

    private sealed class TvdbSearchItem
    {
        [JsonPropertyName("tvdb_id")]
        public string? TvdbId { get; set; }

        [JsonPropertyName("objectID")]
        public string? ObjectId { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("image_url")]
        public string? ImageUrl { get; set; }

        [JsonPropertyName("overview")]
        public string? Overview { get; set; }

        [JsonPropertyName("year")]
        public string? Year { get; set; }
    }
}
