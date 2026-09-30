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
                break;
            case MediaStatus.OnHold:
                item.FinishedAt = null;
                break;
            case MediaStatus.Dropped:
                item.FinishedAt ??= DateTime.UtcNow;
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
