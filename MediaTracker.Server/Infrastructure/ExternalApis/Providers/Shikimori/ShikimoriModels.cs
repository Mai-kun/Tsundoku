using System.Text.Json.Serialization;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Shikimori;

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

    [JsonPropertyName("synonyms")]
    public List<string>? Synonyms { get; set; }

    [JsonPropertyName("kind")]
    public string? Kind { get; set; }

    [JsonPropertyName("authors")]
    public List<ShikimoriPerson>? Authors { get; set; }
}

internal sealed class ShikimoriPerson
{
    [JsonPropertyName("id")]
    public long Id { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("russian")]
    public string? Russian { get; set; }
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

/// <summary>
/// One row of <c>GET /api/{animes|mangas|ranobe}/{id}/related</c>. Shikimori puts the relation kind in
/// <c>relation</c> (its own vocabulary: sequel, prequel, adaptation...) with a Russian label next to
/// it, and inlines the neighbour as <c>anime</c> or <c>manga</c> — novels answer in the <c>manga</c>
/// slot because ranobe is served by the manga tree.
/// </summary>
internal sealed class ShikimoriRelatedEntry
{
    [JsonPropertyName("relation")]
    public string? Relation { get; set; }

    [JsonPropertyName("relation_russian")]
    public string? RelationRussian { get; set; }

    [JsonPropertyName("anime")]
    public ShikimoriItem? Anime { get; set; }

    [JsonPropertyName("manga")]
    public ShikimoriItem? Manga { get; set; }

    public ShikimoriItem? Target => Anime ?? Manga;
}
