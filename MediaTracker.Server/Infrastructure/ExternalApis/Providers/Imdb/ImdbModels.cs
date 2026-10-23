using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Utilities;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

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
}
