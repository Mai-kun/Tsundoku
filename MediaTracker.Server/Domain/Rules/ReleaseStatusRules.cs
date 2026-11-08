namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Derives the release status a source did not declare from the dates it did declare, and folds
/// every provider's vocabulary into one canonical set (NOT_YET_RELEASED / RELEASING / FINISHED /
/// HIATUS / CANCELLED). Reference series are the vocabulary the UI already displays.
/// </summary>
public static class ReleaseStatusRules
{
    public const string NotYetReleased = "NOT_YET_RELEASED";
    public const string Releasing = "RELEASING";
    public const string Finished = "FINISHED";
    public const string Hiatus = "HIATUS";
    public const string Cancelled = "CANCELLED";

    public static string? FromDates(DateTime? releaseDate, DateTime? endDate, DateTime? now = null)
    {
        var today = (now ?? DateTime.UtcNow).Date;

        if (endDate is { } end && end <= today)
        {
            return Finished;
        }

        if (releaseDate is not { } start)
        {
            return null;
        }

        return start.Date > today ? NotYetReleased : Releasing;
    }

    /// <summary>
    /// One canonical status per meaning. Shikimori answers "released" where AniList says
    /// "FINISHED" and TMDb says "Ended" — without the fold, <see cref="AutoRefreshRules"/> only
    /// recognized the literal FINISHED and kept polling completed Shikimori titles forever.
    /// Unrecognized values pass through trimmed and untouched: the UI lets users type a free-text
    /// status, and shouting it into upper case would corrupt what they wrote.
    /// </summary>
    public static string? NormalizeStatus(string? rawStatus)
    {
        if (string.IsNullOrWhiteSpace(rawStatus)) return null;

        var s = rawStatus.Trim().ToUpperInvariant();
        return s switch
        {
            "FINISHED" or "RELEASED" or "COMPLETED" or "ENDED" or "ЗАВЕРШЁН" or "ЗАВЕРШЕНО" => Finished,
            "RELEASING" or "ONGOING" or "AIRING" or "CURRENT" or "ВЫХОДИТ" or "ОНГОИНГ" => Releasing,
            "NOT_YET_RELEASED" or "UPCOMING" or "ANNOUNCED" or "NOT_YET_AIRED" or "АНОНС" or "ANONS" => NotYetReleased,
            "HIATUS" or "PAUSED" or "ЗАМОРОЖЕН" or "ПРИОСТАНОВЛЕН" => Hiatus,
            "CANCELLED" or "CANCELED" or "ОТМЕНЁН" or "DISCONTINUED" => Cancelled,
            _ => rawStatus.Trim(),
        };
    }

    /// <summary>True when the status means "no new content will ever appear" in any spelling.</summary>
    public static bool IsFinishedStatus(string? status) =>
        string.Equals(NormalizeStatus(status), Finished, StringComparison.OrdinalIgnoreCase);
}
