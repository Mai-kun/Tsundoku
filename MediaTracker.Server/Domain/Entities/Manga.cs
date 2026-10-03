namespace MediaTracker.Server.Domain.Entities;

public class Manga : MediaItem
{
    public const int MaxPlaceholderVolumes = 200;

    public int CurrentChapter { get; set; }

    public int? TotalChapters { get; set; }

    public string? Author { get; set; }

    public string? RomajiTitle { get; set; }

    /// <summary>manga / manhwa / manhua / oel, derived from the external source. Null when unknown.</summary>
    public string? Format { get; set; }

    public int CurrentVolume { get; set; }

    public int? TotalVolumes { get; set; }

    public List<MangaVolume> Volumes { get; set; } = [];

    /// <summary>
    /// The chapter stepper's write: clamps to the known chapter count and derives the status, so
    /// finishing the last chapter completes the series without the caller deciding it.
    /// </summary>
    public void SetChapter(int chapter)
    {
        CurrentChapter = TotalChapters is > 0
            ? Math.Min(Math.Max(chapter, 0), TotalChapters.Value)
            : Math.Max(chapter, 0);

        Status = ResolveMangaStatus(CurrentChapter, TotalChapters);
    }

    public void AdvanceToVolume(int volumeNumber) => CurrentVolume = volumeNumber;

    public void RecordTotalVolumes(int totalVolumes) => TotalVolumes = Math.Max(totalVolumes, 0);

    public void RecordTotalChapters(int totalChapters) => TotalChapters = Math.Max(totalChapters, 0);

    public void RecordFormat(string? format) => Format = format;

    /// <summary>Adds a volume to the series, numbering it after the last one when none was given.</summary>
    public MangaVolume AddVolume(MangaVolume volume)
    {
        if (volume.VolumeNumber <= 0)
        {
            volume.VolumeNumber = Volumes.Count + 1;
        }

        Volumes.Add(volume);
        return volume;
    }

    /// <summary>
    /// One stub per requested volume so the detail screen has rows before real data arrives. The
    /// chapter and page budgets are split evenly, which is enough for a progress bar and is
    /// recalculated on refresh once the provider reports the real counts.
    /// </summary>
    public void SeedPlaceholderVolumes(int? requestedVolumes, int? totalChapters, int? totalPages)
    {
        if (Volumes.Count > 0)
        {
            return;
        }

        var volumeCount = requestedVolumes is > 0
            ? Math.Min(requestedVolumes.Value, MaxPlaceholderVolumes)
            : 1;

        for (var volumeNumber = 1; volumeNumber <= volumeCount; volumeNumber++)
        {
            var chaptersPerVolume = SplitEvenly(totalChapters, volumeCount, defaultValue: 0);

            Volumes.Add(new MangaVolume
            {
                VolumeNumber = volumeNumber,
                Title = $"Volume {volumeNumber}",
                TotalChapters = chaptersPerVolume,
                TotalPages = SplitEvenly(totalPages, volumeCount, defaultValue: MangaVolume.PlaceholderPagesPerVolume),
                Status = ResolveMangaStatus(0, chaptersPerVolume),
            });
        }

        TotalVolumes = TotalVolumes is null or 0 ? volumeCount : TotalVolumes;

        if (CurrentVolume <= 0)
        {
            CurrentVolume = 1;
        }
    }

    public static MediaStatus ResolveMangaStatus(int currentChapter, int? totalChapters) =>
        totalChapters is > 0 && currentChapter >= totalChapters.Value
            ? MediaStatus.Completed
            : currentChapter > 0 ? MediaStatus.InProgress : MediaStatus.Planned;

    protected override void ClearProgress()
    {
        CurrentChapter = 0;
        CurrentVolume = 0;
    }

    protected override void MarkProgressAsFinished()
    {
        if (TotalChapters is > 0)
        {
            CurrentChapter = TotalChapters.Value;
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
