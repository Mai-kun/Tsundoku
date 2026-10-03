using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.UpdateMedia;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Copies an <see cref="UpdateMediaRequest"/> onto a tracked entity. Almost every field is nullable
/// in the request, so "not supplied" and "explicitly null" are indistinguishable — the established
/// behaviour is to leave the stored value alone, which is what the null-coalescing preserves.
/// </summary>
public static class MediaItemUpdater
{
    public static void Apply(MediaItem item, UpdateMediaRequest request)
    {
        item.Title = request.Title ?? item.Title;
        item.Score = request.Score ?? item.Score;
        item.Notes = request.Notes ?? item.Notes;
        item.CoverUrl = request.CoverUrl ?? item.CoverUrl;
        item.StartedAt = request.StartedAt ?? item.StartedAt;
        item.FinishedAt = request.FinishedAt ?? item.FinishedAt;
        item.TranslatedSynopsis = request.TranslatedSynopsis ?? item.TranslatedSynopsis;
        item.TranslationLanguage = request.TranslationLanguage ?? item.TranslationLanguage;
        item.Genres = request.Genres ?? item.Genres;
        item.Tags = request.Tags ?? item.Tags;
        item.UnlockedAchievements = request.UnlockedAchievements ?? item.UnlockedAchievements;
        item.WatchedOn = request.ClearWatchedOn ? null : request.WatchedOn ?? item.WatchedOn;
        item.UserPlatform = request.ClearUserPlatform ? null : request.UserPlatform ?? item.UserPlatform;
        item.FranchiseOrder = request.FranchiseOrder ?? item.FranchiseOrder;
        // Both are written together by the client: one pick of a source replaces the cached list.
        item.RelatedMediaJson = request.RelatedMediaJson ?? item.RelatedMediaJson;
        item.RelatedSource = request.RelatedSource ?? item.RelatedSource;

        if (request.Status is { } status)
        {
            item.SetStatus(status);
        }

        ApplyTypeSpecific(item, request);
    }

    private static void ApplyTypeSpecific(MediaItem item, UpdateMediaRequest request)
    {
        switch (item)
        {
            case VideoGame game:
                game.Platform = request.Platform ?? game.Platform;
                game.UserPlatform = request.UserPlatform ?? game.UserPlatform;
                break;
            case Book book:
                book.Author = request.Author ?? book.Author;
                book.TotalPages = request.TotalPages ?? book.TotalPages;
                book.CurrentPage = request.CurrentPage ?? book.CurrentPage;
                break;
            case Manga manga:
                manga.Author = request.Author ?? manga.Author;
                manga.RomajiTitle = request.RomajiTitle ?? manga.RomajiTitle;
                manga.TotalVolumes = request.TotalVolumes ?? manga.TotalVolumes;
                manga.CurrentVolume = request.CurrentVolume ?? manga.CurrentVolume;
                manga.TotalChapters = request.TotalChapters ?? manga.TotalChapters;
                manga.CurrentChapter = request.CurrentChapter ?? manga.CurrentChapter;
                break;
        }
    }
}
