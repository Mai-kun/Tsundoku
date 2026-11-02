namespace MediaTracker.Server.Infrastructure.ExternalApis.Offline;

public sealed class OfflineExtraData
{
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
