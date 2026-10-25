using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Infrastructure.Persistence;

namespace MediaTracker.Server.Features.Media.Import;

/// <summary>
/// Fills a library row from a match that has been chosen — automatically by the confidence scorer or
/// explicitly by the user in the review dialog. Overwrites metadata fully (official WebP cover, total
/// chapters/episodes, genres, staff, ratings) while preserving user progress, status, score and notes.
/// </summary>
public static class PendingMatchApplier
{
    public static async Task<bool> ApplyAsync(
        AppDbContext db,
        MediaItem item,
        ExternalMediaDto match,
        IImageStorageService imageStorage,
        CancellationToken ct,
        Action<TvSeason>? trackNewSeason = null)
    {
        if (match is null)
        {
            return false;
        }

        // 1. Remember user fields
        var userStatus = item.Status;
        var userScore = item.Score;
        var userNotes = item.Notes;
        var userChapter = item is Manga m ? m.CurrentChapter : 0;
        var userVolume = item is Manga mVol ? mVol.CurrentVolume : 0;
        var userPage = item is Book b ? b.CurrentPage : 0;
        var userHours = item is VideoGame g ? g.HoursPlayed : 0;

        var preservedImportSource = !string.IsNullOrWhiteSpace(item.ImportSource)
            ? item.ImportSource
            : item.ExternalSource;
        var preservedRussianTitle = IsCyrillic(item.Title) ? item.Title : null;

        // 2. Full metadata overwrite (downloads official cover as WebP, fills synopsis, totals, cast, ratings, etc.)
        await MediaMetadataApplier.ApplyOverwriteAsync(item, match, imageStorage, ct, trackNewSeason);

        // 3. Restore user progress, status, score and notes
        item.SetStatus(userStatus);
        item.Score = userScore;
        if (userNotes is not null)
        {
            item.Notes = userNotes;
        }

        if (item is Manga manga)
        {
            manga.CurrentChapter = userChapter;
            manga.CurrentVolume = userVolume;
        }
        else if (item is Book book)
        {
            book.CurrentPage = userPage;
        }
        else if (item is VideoGame game)
        {
            game.HoursPlayed = userHours;
        }

        // 4. Handle title preservation for Cyrillic titles vs Latin
        if (!string.IsNullOrWhiteSpace(preservedRussianTitle))
        {
            item.Title = preservedRussianTitle;
            var candidateRomaji = match.RomajiTitle ?? match.Title;
            if (item is Manga mangaItem && !string.IsNullOrWhiteSpace(candidateRomaji))
            {
                mangaItem.RomajiTitle = candidateRomaji;
            }
            else if (item is Movie movieItem && !string.IsNullOrWhiteSpace(candidateRomaji))
            {
                movieItem.RomajiTitle = candidateRomaji;
            }
            else if (item is TvShow tvShowItem && !string.IsNullOrWhiteSpace(candidateRomaji))
            {
                tvShowItem.RomajiTitle = candidateRomaji;
            }

            if (!string.IsNullOrWhiteSpace(match.OriginalTitle))
            {
                item.OriginalTitle = match.OriginalTitle;
            }
            else if (!string.IsNullOrWhiteSpace(candidateRomaji) && string.IsNullOrWhiteSpace(item.OriginalTitle))
            {
                item.OriginalTitle = candidateRomaji;
            }
        }
        else if (!string.IsNullOrWhiteSpace(match.Title))
        {
            item.Title = match.Title;
        }

        // 5. ExternalSource & ImportSource
        if (!string.IsNullOrWhiteSpace(match.ExternalSource))
        {
            item.ExternalSource = match.ExternalSource;
        }
        item.ImportSource = preservedImportSource;

        // 6. Update auto-refresh schedule
        AutoRefreshRules.ApplyRefreshSchedule(item, false, DateTime.UtcNow);

        item.SyncStatus = SyncStatus.Ready;
        item.PendingMatchesJson = null;
        item.MarkUpdated();
        await db.SaveChangesAsync(ct);

        return true;
    }

    private static bool IsCyrillic(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Any(c => char.IsBetween(c, '\u0400', '\u04FF'));

    /// <summary>Keep the row as-is: the user chose not to link anything to it.</summary>
    public static void Dismiss(MediaItem item)
    {
        item.PendingMatchesJson = null;
        item.SyncStatus = SyncStatus.Ready;
        item.MarkUpdated();
    }
}
