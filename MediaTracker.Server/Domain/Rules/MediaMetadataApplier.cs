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
    /// <summary>
    /// Drops the rating rows whose source the user has switched off.
    ///
    /// Refresh only ever writes what the queried source reported, so a badge from a source that was
    /// disabled afterwards stayed on the card forever: nothing in the codebase removed one. Returns
    /// true when the stored payload changed.
    /// </summary>
    /// <param name="disabledSourceIds">Provider ids from settings, matched through the alias table.</param>
    public static bool RemoveDisabledRatings(MediaItem item, IReadOnlySet<string> disabledSourceIds)
    {
        if (string.IsNullOrWhiteSpace(item.ExternalRatingsJson) || disabledSourceIds.Count == 0)
        {
            return false;
        }

        List<RatingSnapshot> kept;
        try
        {
            var stored = JsonSerializer.Deserialize<List<StoredRating>>(
                item.ExternalRatingsJson,
                MediaRatingSerializer.ReadOptions);
            kept =
            [
                .. stored?
                    .Where(rating => !string.IsNullOrWhiteSpace(rating.Source))
                    .Where(rating => !IsDisabled(rating.Source, disabledSourceIds))
                    .Select(rating => new RatingSnapshot(rating.Source, rating.Score, rating.Votes))
                    ?? []
            ];
        }
        catch (JsonException)
        {
            // Unreadable payload: leave it rather than wipe ratings we could not parse.
            return false;
        }

        if (kept.Count == 0)
        {
            if (item.ExternalRatingsJson is null)
            {
                return false;
            }

            item.ExternalRatingsJson = null;
            item.ExternalRating = null;
            item.ExternalRatingVotes = null;
            return true;
        }

        var serialized = MediaRatingSerializer.Serialize(kept);
        if (serialized == item.ExternalRatingsJson)
        {
            return false;
        }

        item.ExternalRatingsJson = serialized;
        return true;
    }

    private static bool IsDisabled(string source, IReadOnlySet<string> disabled) =>
        disabled.Contains(MediaMerger.NormalizeSourceKey(source))
        || disabled.Contains(MediaMerger.GetCanonicalSourceName(source));

    /// <summary>Persisted casing varies by provider, so both spellings are accepted.</summary>
    private sealed record StoredRating(string Source, double Score, int? Votes);

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
        Action<TvSeason>? trackNewSeason = null,
        Action<MangaVolume>? trackNewVolume = null)
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
        ApplyTypeSpecific(item, external, trackNewSeason, trackNewVolume);
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
        Action<TvSeason>? trackNewSeason = null,
        Action<MangaVolume>? trackNewVolume = null)
    {
        var modified = ApplyRatings(item, external);
        modified |= ApplyMangaGaps(item, external, trackNewVolume);

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

            case Book book:
                // Books had no branch here at all, so enrichment never wrote the page count: only an
                // explicit refresh (ApplyTypeSpecific) did. A book added from a search kept 0 pages
                // even when a source had already reported the real length.
                if (book.TotalPages <= 0 && external.TotalCount is > 0)
                {
                    book.TotalPages = external.TotalCount.Value;
                    modified = true;
                }

                modified |= SetIfBlank(book.Author, external.Author, value => book.Author = value);
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
        if (external.Seasons is { Count: > 0 } seasons)
        {
            var before = show.Seasons.Count;
            ApplyRealSeasons(show, seasons, trackNewSeason);
            return show.Seasons.Count > before;
        }

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

    internal static bool ApplyRatings(MediaItem item, ExternalMediaDto external)
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

    private static bool ApplyMangaGaps(
        MediaItem item,
        ExternalMediaDto external,
        Action<MangaVolume>? trackNewVolume)
    {
        if (item is not Manga manga)
        {
            return false;
        }

        var modified = false;

        var before = manga.Volumes.Count;
        ApplyRealVolumes(manga, external.VolumeDetails, trackNewVolume);
        modified |= manga.Volumes.Count > before;

        if (external.Chapters is { } chapters && manga.TotalChapters is not > 0)
        {
            manga.RecordTotalChapters(chapters);
            modified = true;
        }

        // The real volume split is the most accurate chapter count the source ever gives us. The
        // series counter is what both the card and "Характеристики" read, so leaving it on the
        // older flat number is what put 109 next to 135 for the same title.
        var fromVolumes = manga.Volumes.Count > 0
            ? manga.Volumes.Sum(volume => volume.TotalChapters)
            : 0;
        if (fromVolumes > (manga.TotalChapters ?? 0))
        {
            manga.RecordTotalChapters(fromVolumes);
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
        Action<TvSeason>? trackNewSeason,
        Action<MangaVolume>? trackNewVolume)
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
                ApplyRealVolumes(manga, external.VolumeDetails, trackNewVolume);
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
        if (external.Seasons is { Count: > 0 } seasons)
        {
            ApplyRealSeasons(show, seasons, trackNewSeason);
            return;
        }

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

    /// <summary>
    /// Writes one <see cref="TvSeason"/> per season the source reported. Season numbers are matched
    /// against what is already stored, so a refresh updates the existing rows instead of piling up
    /// duplicates, and only numbers that are missing are created.
    /// </summary>
    private static void ApplyRealSeasons(
        TvShow show,
        IReadOnlyList<ExternalSeasonDto> seasons,
        Action<TvSeason>? trackNewSeason)
    {
        foreach (var external in seasons.Where(season => season.TotalEpisodes > 0))
        {
            var episodesJson = external.Episodes is { Count: > 0 } list
                ? JsonSerializer.Serialize(list, MediaRatingSerializer.JsonOptions)
                : null;

            var existing = show.Seasons.FirstOrDefault(season => season.SeasonNumber == external.Number);
            if (existing is null)
            {
                show.Seasons.Add(
                    TvSeason.CreateSeason(external.Number, external.Title, external.TotalEpisodes, episodesJson, show.Status, show.Id)
                );
                trackNewSeason?.Invoke(show.Seasons[^1]);
                continue;
            }

            existing.ApplyEpisodeData(external.TotalEpisodes, episodesJson ?? existing.EpisodesData);
        }
    }

    /// <summary>
    /// Writes the real volume -> chapter split a source reported. Volumes the user already tracks keep
    /// their progress; their chapter count is filled only when they have none, and volumes that do not
    /// exist yet are added.
    /// </summary>
    /// <remarks>
    /// Public so background enrichment can apply a volume split it fetched from a *different* provider
    /// than the one the item came from (see MangaVolumeStructure).
    /// </remarks>
    public static void ApplyRealVolumes(
        Manga manga,
        IReadOnlyList<ExternalMangaVolumeDto>? volumeDetails,
        Action<MangaVolume>? trackNewVolume)
    {
        if (volumeDetails is not { Count: > 0 } details)
        {
            return;
        }

        foreach (var external in details.Where(volume => volume.Number > 0))
        {
            // The number of keys in the source's chapter map, which is what it means as chapters:
            // the sibling `count` field counts translations, not chapters.
            var chapterCount = external.Chapters?.Count ?? 0;
            var existing = manga.Volumes.FirstOrDefault(volume => volume.VolumeNumber == external.Number);
            if (existing is null)
            {
                var created = new MangaVolume
                {
                    MangaId = manga.Id,
                    VolumeNumber = external.Number,
                    Title = string.IsNullOrWhiteSpace(external.Title) ? $"Volume {external.Number}" : external.Title,
                    TotalChapters = chapterCount,
                    TotalPages = MangaVolume.PlaceholderPagesPerVolume,
                };
                manga.Volumes.Add(created);
                trackNewVolume?.Invoke(created);
                continue;
            }

            // A chapter count the user typed is kept; only a volume that never learned its own takes
            // the source's number.
            if (chapterCount > 0 && existing.TotalChapters == 0)
            {
                existing.InheritTotalChapters(chapterCount);
            }
        }

        manga.RecordTotalVolumes(manga.Volumes.Count);
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
