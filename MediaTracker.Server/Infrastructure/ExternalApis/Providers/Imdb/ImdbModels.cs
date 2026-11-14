using System.Text.Json;
using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Imdb;

internal sealed class ImdbSuggestionResponse
{
    [JsonPropertyName("d")]
    public List<ImdbSuggestionItem>? D { get; set; }
}

internal sealed class ImdbSuggestionItem
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("l")]
    public string? L { get; set; }

    [JsonPropertyName("y")]
    public int? Y { get; set; }

    [JsonPropertyName("q")]
    public string? Q { get; set; }

    [JsonPropertyName("qid")]
    public string? Qid { get; set; }

    [JsonPropertyName("i")]
    public ImdbImage? I { get; set; }
}

internal sealed class ImdbImage
{
    [JsonPropertyName("imageUrl")]
    public string? ImageUrl { get; set; }
}

internal sealed class CinemetaResponse
{
    [JsonPropertyName("meta")]
    public CinemetaMeta? Meta { get; set; }
}

internal sealed class CinemetaMeta
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("type")]
    public string? Type { get; set; }

    [JsonPropertyName("imdbRating")]
    public JsonElement? ImdbRating { get; set; }

    [JsonPropertyName("runtime")]
    public string? Runtime { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("genres")]
    public List<string>? Genres { get; set; }

    [JsonPropertyName("votes")]
    public JsonElement? Votes { get; set; }

    /// <summary>
    /// Series only: the full episode tree Cinemeta carries from TVDB — one entry per episode with
    /// its season, number, title, air date and overview.
    /// </summary>
    [JsonPropertyName("videos")]
    public List<CinemetaVideo>? Videos { get; set; }
}

/// <summary>One episode of a Cinemeta series meta ("tt0944947:1:1").</summary>
internal sealed class CinemetaVideo
{
    [JsonPropertyName("season")]
    public int Season { get; set; }

    [JsonPropertyName("episode")]
    public int Episode { get; set; }

    /// <summary>Older metas number the episode here instead of the "episode" field.</summary>
    [JsonPropertyName("number")]
    public int? Number { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("released")]
    public string? Released { get; set; }

    [JsonPropertyName("overview")]
    public string? Overview { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("thumbnail")]
    public string? Thumbnail { get; set; }
}
