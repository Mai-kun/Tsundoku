namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

using System.Text.Encodings.Web;
using System.Text.Json;
using MediaTracker.Server.Common.Json;

public sealed class OfflineExtraData
{
    /// <summary>
    /// The options the blob is stored with. The default encoder \uXXXX-escapes every non-ASCII
    /// character, which buried Cyrillic synonyms inside an ASCII-only JSON blob no LIKE query
    /// could ever match — the same trap the AltTitles serializer already escaped. Deserialization
    /// is unaffected, so previously written databases keep reading fine and get rewritten in the
    /// readable form by the next genre cleanup.
    /// </summary>
    public static readonly JsonSerializerOptions SerializerOptions = new(AppJsonSerializerContext.Default.Options)
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public string? CoverUrl { get; set; }
    public string? Description { get; set; }
    public string? Format { get; set; }
    public int? TotalCount { get; set; }
    public int? RuntimeMinutes { get; set; }
    public string? ReleaseStatus { get; set; }
    public string? Studio { get; set; }
    public string? Developer { get; set; }
    public string? Publisher { get; set; }
    public string? Platform { get; set; }
    public List<string>? Synonyms { get; set; }
    public List<string>? Tags { get; set; }
    public string? AnilistId { get; set; }
    public string? MalId { get; set; }
    public string? KitsuId { get; set; }
    public string? AnidbId { get; set; }
    public string? ImdbId { get; set; }
    public string? SteamAppId { get; set; }
}
