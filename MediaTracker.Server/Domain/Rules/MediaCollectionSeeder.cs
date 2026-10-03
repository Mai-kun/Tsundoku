using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Creates the placeholder season or volume rows the UI needs before real provider data arrives.
/// </summary>
public static class MediaCollectionSeeder
{
    public static void SeedPlaceholderSeasons(MediaItem item, Features.Media.CreateMedia.CreateMediaRequest request)
    {
        if (item is not TvShow show || show.Seasons.Count > 0)
        {
            return;
        }

        // A live-action show used to be excluded outright, so one created from a search hit with a
        // known episode count and no season list kept an empty accordion and rendered "0 / 0".
        var episodeCount = ResolveEpisodeCount(request);
        if (episodeCount <= 0)
        {
            return;
        }

        show.Seasons.Add(TvSeason.CreateFirst(episodeCount, episodesData: null, show.Status, show.Id));
    }

    /// <summary>
    /// How many episodes the create request claims to know about. The seasons the client sends are
    /// the only trustworthy source: the flat fields carry runtime and page counts for other media
    /// types, so reading an episode total out of them invented a season length.
    /// </summary>
    private static int ResolveEpisodeCount(Features.Media.CreateMedia.CreateMediaRequest request)
    {
        var fromSeasons = request.Seasons?.Sum(season => season.TotalEpisodes) ?? 0;
        return fromSeasons > 0 ? fromSeasons : 0;
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
