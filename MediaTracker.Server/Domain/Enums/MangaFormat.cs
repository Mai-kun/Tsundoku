namespace MediaTracker.Server.Domain.Enums;

/// <summary>
/// The four origin buckets the UI distinguishes. Sources disagree on wording, so the raw signal is
/// normalized into this enum at the edge and only the domain does the ranking.
/// </summary>
public enum MangaFormat
{
    Manga = 0,
    Manhwa = 1,
    Manhua = 2,
    Oel = 3,
}
