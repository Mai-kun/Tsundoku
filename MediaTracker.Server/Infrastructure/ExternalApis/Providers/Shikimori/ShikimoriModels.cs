using System.Globalization;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class ShikimoriItem
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("russian")]
    public string? Russian { get; set; }

    [JsonPropertyName("japanese")]
    public List<string>? Japanese { get; set; }

    [JsonPropertyName("image")]
    public ShikimoriImage? Image { get; set; }

    [JsonPropertyName("score")]
    public string? Score { get; set; }

    [JsonPropertyName("status")]
    public string? Status { get; set; }

    [JsonPropertyName("episodes")]
    public int? Episodes { get; set; }

    [JsonPropertyName("chapters")]
    public int? Chapters { get; set; }

    [JsonPropertyName("volumes")]
    public int? Volumes { get; set; }

    [JsonPropertyName("aired_on")]
    public string? AiredOn { get; set; }

    [JsonPropertyName("released_on")]
    public string? ReleasedOn { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("genres")]
    public List<ShikimoriGenre>? Genres { get; set; }
}

internal sealed class ShikimoriGenre
{
    [JsonPropertyName("russian")]
    public string? Russian { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }
}

internal sealed class ShikimoriImage
{
    [JsonPropertyName("original")]
    public string? Original { get; set; }

    [JsonPropertyName("preview")]
    public string? Preview { get; set; }
}
