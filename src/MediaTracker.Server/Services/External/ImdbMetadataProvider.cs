using System.Text.Json.Serialization;

namespace MediaTracker.Server.Services.External;

public sealed class ImdbMetadataProvider(IHttpClientFactory httpClientFactory) : IMetadataProvider
{
    public string Id => "imdb";
    public string Name => "IMDb";
    public string Description => "Internet Movie Database movies and TV shows metadata provider";
    public IReadOnlyList<string> MediaTypes => ["movie", "tvshow"];

    public async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var clean = query.Trim();
        if (clean.Length == 0) return [];

        var firstChar = char.IsLetterOrDigit(clean[0]) ? clean[0].ToString().ToLowerInvariant() : "a";
        var client = httpClientFactory.CreateClient("Imdb");
        var endpoint = $"{firstChar}/{Uri.EscapeDataString(clean.ToLowerInvariant())}.json";

        try
        {
            var res = await client.GetFromJsonAsync<ImdbSuggestionResponse>(endpoint, ct);
            if (res?.D is null || res.D.Count == 0)
            {
                return [];
            }

            return res.D
                .Where(item => !string.IsNullOrWhiteSpace(item.Id) && !string.IsNullOrWhiteSpace(item.L))
                .Select(MapItem)
                .ToList();
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
        var results = await SearchAsync(!string.IsNullOrWhiteSpace(title) ? title : externalId, ct);
        return results.FirstOrDefault(r => r.ExternalId.Equals(externalId, StringComparison.OrdinalIgnoreCase))
               ?? (results.Count > 0 ? results[0] : null);
    }

    private static ExternalMediaDto MapItem(ImdbSuggestionItem item)
    {
        var isTv = item.Q is not null && (item.Q.Contains("tv", StringComparison.OrdinalIgnoreCase) || item.Q.Contains("series", StringComparison.OrdinalIgnoreCase));
        var type = isTv ? "tvshow" : "movie";

        return new ExternalMediaDto
        {
            ExternalId = item.Id,
            ExternalSource = "IMDb",
            Title = item.L ?? "Unknown",
            CoverUrl = item.I?.ImageUrl,
            ReleaseYear = item.Y,
            Studio = item.S,
            Type = type,
            Ratings = []
        };
    }

    private sealed class ImdbSuggestionResponse
    {
        [JsonPropertyName("d")]
        public List<ImdbSuggestionItem>? D { get; set; }
    }

    private sealed class ImdbSuggestionItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("l")]
        public string? L { get; set; }

        [JsonPropertyName("y")]
        public int? Y { get; set; }

        [JsonPropertyName("q")]
        public string? Q { get; set; }

        [JsonPropertyName("s")]
        public string? S { get; set; }

        [JsonPropertyName("i")]
        public ImdbImage? I { get; set; }
    }

    private sealed class ImdbImage
    {
        [JsonPropertyName("imageUrl")]
        public string? ImageUrl { get; set; }
    }
}
