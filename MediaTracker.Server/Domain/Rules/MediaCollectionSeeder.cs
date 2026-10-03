using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Creates the placeholder season or volume rows the UI needs before real provider data arrives.
/// </summary>
public static class MediaCollectionSeeder
{
    public static void SeedPlaceholderSeasons(MediaItem item, Features.Media.CreateMedia.CreateMediaRequest request)
    {
        if (item is not TvShow { IsAnime: true } show || show.Seasons.Count > 0)
        {
            return;
        }

        var episodeCount = request.DurationMinutes ?? request.TotalPages ?? request.TotalChapters ?? 0;
        if (episodeCount <= 0)
        {
            return;
        }

        show.Seasons.Add(TvSeason.CreateFirst(episodeCount, episodesData: null, show.Status, show.Id));
    }

    public static void SeedPlaceholderVolumes(MediaItem item, Features.Media.CreateMedia.CreateMediaRequest request)
    {
        if (item is not Manga manga)
        {
            return;
        }

        manga.SeedPlaceholderVolumes(request.TotalVolumes, request.TotalChapters, request.TotalPages);
    }
}
