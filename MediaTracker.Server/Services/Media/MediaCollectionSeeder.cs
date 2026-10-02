using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;

namespace MediaTracker.Server.Services.Media;

/// <summary>
/// Creates the placeholder season/volume rows the UI needs before real provider data arrives.
/// The even chapter/page split is good enough for a progress bar and is recalculated on refresh
/// once the real counts are known.
/// </summary>
public static class MediaCollectionSeeder
{
    private const int MaxPlaceholderVolumes = 200;
    private const int DefaultPagesPerVolume = 200;

    public static void SeedPlaceholderSeasons(MediaItem item, CreateMediaRequest request)
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

        show.Seasons.Add(new TvSeason
        {
            SeasonNumber = 1,
            Title = "Season 1",
            TotalEpisodes = episodeCount,
            Status = show.Status
        });
    }

    public static void SeedPlaceholderVolumes(MediaItem item, CreateMediaRequest request)
    {
        if (item is not Manga manga || manga.Volumes.Count > 0)
        {
            return;
        }

        var volumeCount = request.TotalVolumes is > 0
            ? Math.Min(request.TotalVolumes.Value, MaxPlaceholderVolumes)
            : 1;

        for (var volumeNumber = 1; volumeNumber <= volumeCount; volumeNumber++)
        {
            manga.Volumes.Add(new MangaVolume
            {
                VolumeNumber = volumeNumber,
                Title = $"Volume {volumeNumber}",
                TotalChapters = SplitEvenly(request.TotalChapters, volumeCount, defaultValue: 0),
                TotalPages = SplitEvenly(request.TotalPages, volumeCount, defaultValue: DefaultPagesPerVolume),
                Status = manga.Status
            });
        }

        if (manga.TotalVolumes is null or 0)
        {
            manga.TotalVolumes = volumeCount;
        }

        if (manga.CurrentVolume <= 0)
        {
            manga.CurrentVolume = 1;
        }
    }

    private static int SplitEvenly(int? total, int parts, int defaultValue)
    {
        if (total is null || parts <= 0)
        {
            return defaultValue;
        }

        return (int)Math.Ceiling((double)total.Value / parts);
    }
}
