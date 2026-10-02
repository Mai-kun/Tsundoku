using MediaTracker.Server.Models;

namespace MediaTracker.Server.Services.Media;

/// <summary>
/// Keeps started/finished timestamps and type-specific progress counters consistent with a status
/// change, so a "completed" show does not keep un-watched seasons.
/// </summary>
public static class MediaStatusTransitions
{
    public static void Apply(MediaItem item, MediaStatus status)
    {
        switch (status)
        {
            case MediaStatus.Completed:
                item.FinishedAt ??= DateTime.UtcNow;
                MarkProgressAsFinished(item);
                break;
            case MediaStatus.InProgress:
                item.StartedAt ??= DateTime.UtcNow;
                item.FinishedAt = null;
                break;
            case MediaStatus.Planned:
                item.StartedAt = null;
                item.FinishedAt = null;
                ClearProgress(item);
                break;
            case MediaStatus.OnHold:
                item.FinishedAt = null;
                break;
            case MediaStatus.Dropped:
                item.FinishedAt ??= DateTime.UtcNow;
                break;
        }
    }

    /// <summary>
    /// "Planned" means nothing has been started yet, so a title moved back to it must not keep the
    /// counters it accumulated — otherwise a planned anime reads as 220/220 and every progress bar
    /// (card, banner, spec sheet) is full while the status says otherwise.
    /// </summary>
    private static void ClearProgress(MediaItem item)
    {
        switch (item)
        {
            case TvShow show:
                foreach (var season in show.Seasons)
                {
                    season.CurrentEpisode = 0;
                    season.Status = MediaStatus.Planned;
                }

                break;
            case Book book:
                book.CurrentPage = 0;
                break;
            case Manga manga:
                manga.CurrentChapter = 0;
                manga.CurrentVolume = 0;
                break;
            case VideoGame game:
                game.HoursPlayed = 0;
                break;
        }
    }

    private static void MarkProgressAsFinished(MediaItem item)
    {
        switch (item)
        {
            case TvShow show:
                foreach (var season in show.Seasons)
                {
                    season.CurrentEpisode = season.TotalEpisodes;
                    season.Status = MediaStatus.Completed;
                }
                break;
            case Book book when book.TotalPages > 0:
                book.CurrentPage = book.TotalPages;
                break;
            case Manga manga when manga.TotalChapters is > 0:
                manga.CurrentChapter = manga.TotalChapters.Value;
                break;
        }
    }
}
