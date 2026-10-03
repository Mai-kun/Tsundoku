using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>
/// Maps external provider metadata onto a tracked <see cref="MediaItem"/>. Refresh (overwrite) and
/// enrich (fill gaps) walk the same type hierarchy, so both live here to stop them drifting apart.
/// Every mutating helper reports whether it actually changed anything, which is what lets enrich
/// return "no change" without diffing the whole entity afterwards.
/// </summary>
public static class MediaMetadataApplier
{
    /// <summary>Persisted shape is <c>source/score/votes</c>; that is the field name the UI reads first.</summary>
    public static string SerializeRatings(IReadOnlyList<ExternalRatingDto> ratings) =>
        MediaRatingSerializer.Serialize(
            ratings.Select(rating => new RatingSnapshot(rating.Source, rating.Rating, rating.Votes)));

    public static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    /// <summary>Refresh: external data is authoritative and overwrites whatever is stored.</summary>
    public static async Task ApplyOverwriteAsync(
        MediaItem item,
        ExternalMediaDto external,
        IImageStorageService imageStorage,
        CancellationToken ct,
        Action<TvSeason>? trackNewSeason = null)
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
        ApplyTypeSpecific(item, external, trackNewSeason);
    }

    /// <summary>Enrich: only fills fields the user has not filled. Returns true when the entity changed.</summary>
    /// <param name="trackNewSeason">
    /// Marks a season this applier creates as genuinely new. EF otherwise keeps it in
    /// <c>Modified</c> state and saves it as an UPDATE against a row that was never inserted, which
    /// fails the whole save with a <c>DbUpdateConcurrencyException</c> and loses the dates and the
    /// episode count along with it. The applier has no DbContext, so the caller supplies the seam.
    /// </param>
    public static bool ApplyIfMissing(
        MediaItem item,
        ExternalMediaDto external,
        Action<TvSeason>? trackNewSeason = null)
    {
        var modified = ApplyRatings(item, external);
        modified |= ApplyMangaGaps(item, external);

        modified |= SetIfBlank(item.Notes, external.Description, value => item.Notes = value);
        modified |= SetIfBlank(item.Genres, JoinGenres(external.Genres), value => item.Genres = value);
        modified |= ApplyDisplayGaps(item, external, trackNewSeason);

        // Runs last: deriving the status from dates is only correct once the dates themselves are in.
        if (string.IsNullOrWhiteSpace(item.ReleaseStatus))
        {
            var status = !string.IsNullOrWhiteSpace(external.ReleaseStatus)
                ? external.ReleaseStatus
                // No source declared a status, but a past end date or a future start date still
                // decides it, and the row would otherwise stay empty.
                : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate);

            modified |= SetIfBlank(item.ReleaseStatus, status, value => item.ReleaseStatus = value);
        }

        return modified;
    }

    /// <summary>
    /// Enrich only fills what the user has not filled. Runtime and studio were missing from this
    /// path entirely, so background enrichment never produced them and only an explicit refresh did.
    /// </summary>
    private static bool ApplyDisplayGaps(
        MediaItem item,
        ExternalMediaDto external,
        Action<TvSeason>? trackNewSeason = null)
    {
        var modified = false;

        switch (item)
        {
            case Movie movie:
                if (movie.DurationMinutes <= 0 && (external.RuntimeMinutes is > 0 || external.TotalCount is > 0))
                {
                    movie.DurationMinutes = external.RuntimeMinutes ?? external.TotalCount!.Value;
                    modified = true;
                }

                modified |= SetIfBlank(movie.Studio, external.Studio, value => movie.Studio = value);
                modified |= SetIfBlank(movie.Director, external.Author, value => movie.Director = value);
                modified |= SetIfBlank(movie.RomajiTitle, external.OriginalTitle, value => movie.RomajiTitle = value);
                break;

            case TvShow show:
                if (show.EpisodeDurationMinutes is not > 0 && external.RuntimeMinutes is > 0)
                {
                    show.EpisodeDurationMinutes = external.RuntimeMinutes.Value;
                    modified = true;
                }

                if (string.IsNullOrWhiteSpace(show.Studio) && !string.IsNullOrWhiteSpace(external.Studio))
                {
                    show.Studio = external.Studio;
                    show.Network = external.Studio;
                    modified = true;
                }

                // Seasons are created from the episode list when there is one, and from the bare
                // episode count when the source has no per-episode data (TMDb reports 73 episodes,
                // not 73 rows). Only an empty season list is filled, so the user's own seasons are
                // never touched.
                if (show.Seasons.Count == 0)
                {
                    modified |= TryCreateSeason(show, external, trackNewSeason);
                }

                break;
        }

        modified |= SetIfNull(item.ReleaseYear, external.ReleaseYear is > 0 ? external.ReleaseYear : null,
            value => item.ReleaseYear = value);

        modified |= SetIfNull(item.ReleaseDate, ParseDate(external.ReleaseDate),
            value => item.ReleaseDate = value);

        // Enrich never wrote the end date, so a series that had already finished still showed an
        // empty "Дата окончания" until an explicit refresh.
        modified |= SetIfNull(item.EndDate, ParseDate(external.EndDate),
            value => item.EndDate = value);

        return modified;
    }

    private static bool TryCreateSeason(
        TvShow show,
        ExternalMediaDto external,
        Action<TvSeason>? trackNewSeason)
    {
        var episodes = external.Episodes is { Count: > 0 } list ? list : null;
        var totalEpisodes = external.TotalCount ?? episodes?.Count ?? 0;

        if (totalEpisodes <= 0)
        {
            return false;
        }

        var season = TvSeason.CreateFirst(
            totalEpisodes,
            episodes is null ? null : JsonSerializer.Serialize(episodes, MediaRatingSerializer.JsonOptions),
            show.Status,
            show.Id);

        show.Seasons.Add(season);
        trackNewSeason?.Invoke(season);
        return true;
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
            manga.RecordTotalChapters(chapters);
            modified = true;
        }

        if (external.Volumes is { } volumes && manga.TotalVolumes is not > 0)
        {
            manga.RecordTotalVolumes(volumes);
            modified = true;
        }

        modified |= SetIfBlank(manga.Author, external.Author, value => manga.Author = value);
        modified |= SetIfBlank(manga.RomajiTitle, external.RomajiTitle, value => manga.RomajiTitle = value);
        modified |= SetIfBlank(manga.Format, external.MangaFormat, value => manga.Format = value);

        // A single stub volume stands in for the whole series until real volume data arrives.
        if (manga.Volumes is [var onlyVolume] && onlyVolume.TotalChapters == 0 && manga.TotalChapters is > 0)
        {
            onlyVolume.InheritTotalChapters(manga.TotalChapters.Value);
            modified = true;
        }

        return modified;
    }

    private static void ApplyDates(MediaItem item, ExternalMediaDto external)
    {
        // "2021" / "2021-03" mean the source only knows that much; inventing Jan 1 for the missing
        // part is the lie behind "1 January 2021", so the date stays unset and the year is stored raw.
        item.SetReleaseDate(ParseDate(external.ReleaseDate), external.ReleaseYear);
        item.EndDate = ParseDate(external.EndDate);

        item.ReleaseStatus = !string.IsNullOrWhiteSpace(external.ReleaseStatus)
            ? external.ReleaseStatus
            : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate);
    }

    private static void ApplyGenres(MediaItem item, ExternalMediaDto external)
    {
        if (external.Genres is { Count: > 0 } genres)
        {
            item.Genres = string.Join(", ", genres);
        }
    }

    private static void ApplyTypeSpecific(
        MediaItem item,
        ExternalMediaDto external,
        Action<TvSeason>? trackNewSeason)
    {
        switch (item)
        {
            case TvShow show:
                ApplyToTvShow(show, external, trackNewSeason);
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
                if (external.TotalCount is > 0) manga.RecordTotalChapters(external.TotalCount.Value);
                if (external.Chapters is > 0) manga.RecordTotalChapters(external.Chapters.Value);
                if (external.Volumes is > 0) manga.RecordTotalVolumes(external.Volumes.Value);
                if (!string.IsNullOrWhiteSpace(external.Author)) manga.Author = external.Author;
                if (!string.IsNullOrWhiteSpace(external.RomajiTitle)) manga.RomajiTitle = external.RomajiTitle;
                if (!string.IsNullOrWhiteSpace(external.MangaFormat)) manga.RecordFormat(external.MangaFormat);
                break;
            case VideoGame game:
                if (!string.IsNullOrWhiteSpace(external.Platform)) game.Platform = external.Platform;
                break;
        }
    }

    private static void ApplyToTvShow(
        TvShow show,
        ExternalMediaDto external,
        Action<TvSeason>? trackNewSeason)
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

        // The "anime only" guard dropped episode lists for every live-action show, so a Kinopoisk or
        // TMDb series with real per-episode air dates lost them. The list is the source's own data
        // when it is present, so it is written regardless of the anime flag; only its absence was
        // ever a reason to skip.
        if (external.Episodes is not { Count: > 0 } episodes)
        {
            return;
        }

        var totalEpisodes = external.TotalCount ?? episodes.Count;
        var episodesJson = JsonSerializer.Serialize(episodes, MediaRatingSerializer.JsonOptions);

        var firstSeason = show.Seasons.FirstOrDefault();
        if (firstSeason is null)
        {
            var created = TvSeason.CreateFirst(totalEpisodes, episodesJson, show.Status, show.Id);
            show.Seasons.Add(created);
            trackNewSeason?.Invoke(created);
            return;
        }

        firstSeason.ApplyEpisodeData(totalEpisodes, episodesJson);
    }

    private static DateTime? ParseDate(string? value) =>
        DateTime.TryParse(value, out var parsed) ? parsed : null;

    private static string? JoinGenres(IReadOnlyList<string>? genres) =>
        genres is { Count: > 0 } ? string.Join(", ", genres) : null;

    private static bool SetIfBlank(string? current, string? candidate, Action<string> assign)
    {
        if (!string.IsNullOrWhiteSpace(current) || string.IsNullOrWhiteSpace(candidate))
        {
            return false;
        }

        assign(candidate);
        return true;
    }

    private static bool SetIfNull<T>(T? current, T? candidate, Action<T> assign)
        where T : struct
    {
        if (current is not null || candidate is null)
        {
            return false;
        }

        assign(candidate.Value);
        return true;
    }
}
