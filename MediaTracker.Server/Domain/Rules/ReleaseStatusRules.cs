namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Derives the release status a source did not declare from the dates it did declare. Reference
/// series (NOT_YET_RELEASED / RELEASING / FINISHED) are the vocabulary the UI already displays.
/// </summary>
public static class ReleaseStatusRules
{
    public const string NotYetReleased = "NOT_YET_RELEASED";
    public const string Releasing = "RELEASING";
    public const string Finished = "FINISHED";

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
}
