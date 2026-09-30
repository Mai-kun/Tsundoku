using System.Text.Json;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Storage;

namespace MediaTracker.Server.Services.Media;

/// <summary>
/// Maps external provider metadata onto a tracked <see cref="MediaItem"/>. Refresh (overwrite) and
/// enrich (fill gaps) walk the same type hierarchy, so both live here to stop them drifting apart.
/// </summary>
public static class MediaMetadataApplier
{
    private static readonly JsonSerializerOptions CamelCaseJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    /// <summary>Persisted shape is <c>source/score/votes</c>; that is the field name the UI reads first.</summary>
    public static string SerializeRatings(IReadOnlyList<ExternalRatingDto> ratings) =>
        JsonSerializer.Serialize(
            ratings.Select(rating => new { source = rating.Source, score = rating.Rating, votes = rating.Votes }),
            CamelCaseJsonOptions);

    public static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    /// <summary>Refresh: external data is authoritative and overwrites whatever is stored.</summary>
    public static async Task ApplyOverwriteAsync(
        MediaItem item,
        ExternalMediaDto external,
        IImageStorageService imageStorage,
        CancellationToken ct)
    {
        item.Title = external.Title;
        if (!string.IsNullOrWhiteSpace(external.Description))
        {
            item.Notes = external.Description;
        }

        if (IsExternalUrl(external.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(external.CoverUrl!, item.Id, ct);
        }

        item.ExternalId = external.ExternalId;
        item.ExternalSource = external.ExternalSource ?? item.ExternalSource;
        item.ExternalRating = external.Rating;
        item.ExternalRatingVotes = external.RatingVotes;
        if (external.Ratings is { Count: > 0 } ratings)
        {
            item.ExternalRatingsJson = SerializeRatings(ratings);
        }

        ApplyDates(item, external);
        ApplyGenres(item, external);
        ApplyTypeSpecific(item, external);
    }

    /// <summary>Enrich: only fills fields the user has not filled. Returns true when the entity changed.</summary>
    public static bool ApplyIfMissing(MediaItem item, ExternalMediaDto external)
    {
        var modified = ApplyRatings(item, external);
        modified |= ApplyMangaGaps(item, external);

        if (string.IsNullOrWhiteSpace(item.Notes) && !string.IsNullOrWhiteSpace(external.Description))
        {
            item.Notes = external.Description;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(item.Genres) && external.Genres is { Count: > 0 } genres)
        {
            item.Genres = string.Join(", ", genres);
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(item.ReleaseStatus) && !string.IsNullOrWhiteSpace(external.ReleaseStatus))
        {
            item.ReleaseStatus = external.ReleaseStatus;
            modified = true;
        }

        return modified;
    }

    private static bool ApplyRatings(MediaItem item, ExternalMediaDto external)
    {
        if (external.Ratings is not { Count: > 0 } ratings)
        {
            return false;
        }

        item.ExternalRatingsJson = SerializeRatings(ratings);
        if (external.Rating is > 0)
        {
            item.ExternalRating = external.Rating;
            item.ExternalRatingVotes = external.RatingVotes;
        }

        return true;
    }

    private static bool ApplyMangaGaps(MediaItem item, ExternalMediaDto external)
    {
        if (item is not Manga manga)
        {
            return false;
        }

        var modified = false;

        if (external.Chapters is { } chapters && manga.TotalChapters is not > 0)
        {
            manga.TotalChapters = chapters;
            modified = true;
        }

        if (external.Volumes is { } volumes && manga.TotalVolumes is not > 0)
        {
            manga.TotalVolumes = volumes;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(manga.Author) && !string.IsNullOrWhiteSpace(external.Author))
        {
            manga.Author = external.Author;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(manga.RomajiTitle) && !string.IsNullOrWhiteSpace(external.RomajiTitle))
        {
            manga.RomajiTitle = external.RomajiTitle;
            modified = true;
        }

        // A single stub volume stands in for the whole series until real volume data arrives.
        if (manga.Volumes is [var onlyVolume] && onlyVolume.TotalChapters == 0 && manga.TotalChapters is > 0)
        {
            onlyVolume.TotalChapters = manga.TotalChapters.Value;
            modified = true;
        }

        return modified;
    }

    private static void ApplyDates(MediaItem item, ExternalMediaDto external)
    {
        if (DateTime.TryParse(external.ReleaseDate, out var releaseDate))
        {
            item.ReleaseDate = releaseDate;
        }
        else if (external.ReleaseYear is > 0 && item.ReleaseDate is null)
        {
            item.ReleaseDate = new DateTime(external.ReleaseYear.Value, 1, 1);
        }

        if (DateTime.TryParse(external.EndDate, out var endDate))
        {
            item.EndDate = endDate;
        }

        item.ReleaseStatus = !string.IsNullOrWhiteSpace(external.ReleaseStatus)
            ? external.ReleaseStatus
            : MediaItemFactory.ComputeReleaseStatusFromDates(item.ReleaseDate, item.EndDate);
    }

    private static void ApplyGenres(MediaItem item, ExternalMediaDto external)
    {
        if (external.Genres is { Count: > 0 } genres)
        {
            item.Genres = string.Join(", ", genres);
        }
    }

    private static void ApplyTypeSpecific(MediaItem item, ExternalMediaDto external)
    {
        switch (item)
        {
            case TvShow show:
                ApplyToTvShow(show, external);
                break;
            case Movie movie:
                if (external.RuntimeMinutes is > 0) movie.DurationMinutes = external.RuntimeMinutes.Value;
                else if (external.TotalCount is > 0) movie.DurationMinutes = external.TotalCount.Value;
                if (!string.IsNullOrWhiteSpace(external.Studio)) movie.Studio = external.Studio;
                if (!string.IsNullOrWhiteSpace(external.OriginalTitle)) movie.RomajiTitle = external.OriginalTitle;
                break;
            case Book book:
                if (external.TotalCount is > 0) book.TotalPages = external.TotalCount.Value;
                if (!string.IsNullOrWhiteSpace(external.Author)) book.Author = external.Author;
                break;
            case Manga manga:
                if (external.TotalCount is > 0) manga.TotalChapters = external.TotalCount.Value;
                if (external.Chapters is > 0) manga.TotalChapters = external.Chapters.Value;
                if (external.Volumes is > 0) manga.TotalVolumes = external.Volumes.Value;
                if (!string.IsNullOrWhiteSpace(external.Author)) manga.Author = external.Author;
                if (!string.IsNullOrWhiteSpace(external.RomajiTitle)) manga.RomajiTitle = external.RomajiTitle;
                break;
            case VideoGame game:
                if (!string.IsNullOrWhiteSpace(external.Platform)) game.Platform = external.Platform;
                break;
        }
    }

    private static void ApplyToTvShow(TvShow show, ExternalMediaDto external)
    {
        if (external.RuntimeMinutes is > 0)
        {
            show.EpisodeDurationMinutes = external.RuntimeMinutes;
        }

        if (!string.IsNullOrWhiteSpace(external.Studio))
        {
            show.Studio = external.Studio;
            show.Network = external.Studio;
        }

        if (!string.IsNullOrWhiteSpace(external.OriginalTitle))
        {
            show.RomajiTitle = external.OriginalTitle;
        }

        // Only anime carry a per-episode list; live-action shows get episode counts, not episodes.
        if (!show.IsAnime || external.Episodes is not { Count: > 0 } episodes)
        {
            return;
        }

        var totalEpisodes = external.TotalCount ?? episodes.Count;
        var episodesJson = JsonSerializer.Serialize(episodes, CamelCaseJsonOptions);

        var firstSeason = show.Seasons.FirstOrDefault();
        if (firstSeason is null)
        {
            show.Seasons.Add(new TvSeason
            {
                Id = Guid.NewGuid(),
                SeasonNumber = 1,
                Title = "Season 1",
                TvShowId = show.Id,
                Status = show.Status,
                TotalEpisodes = totalEpisodes,
                EpisodesData = episodesJson
            });
            return;
        }

        firstSeason.TotalEpisodes = totalEpisodes;
        firstSeason.EpisodesData = episodesJson;
    }
}
