using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Storage;
using MediaTracker.Server.Features.Media.GetMediaStats;

using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

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
            var stored = JsonSerializer.Deserialize(item.ExternalRatingsJson, AppJsonSerializerContext.Default.ListStoredRating);
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
    internal sealed record StoredRating(string Source, double Score, int? Votes);

    /// <summary>Persisted shape is <c>source/score/votes</c>; that is the field name the UI reads first.</summary>
    public static string SerializeRatings(IReadOnlyList<ExternalRatingDto> ratings) =>
        MediaRatingSerializer.Serialize(
            ratings.Select(rating => new RatingSnapshot(rating.Source, rating.Rating, rating.Votes)));

    public static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// True when the row's active poster IS the given gallery variant. The URL is compared without
    /// its query part: the UI appends a cache-buster, and DeleteAsync tolerates it the same way.
    /// </summary>
    private static bool MatchesActiveCover(string? activeCoverUrl, MediaCoverItemDto variant) =>
        activeCoverUrl is not null
        && (activeCoverUrl.Split('?')[0].Equals(variant.ThumbUrl, StringComparison.OrdinalIgnoreCase)
            || activeCoverUrl.Split('?')[0].Equals(variant.OriginalUrl, StringComparison.OrdinalIgnoreCase));

    private static bool ContainsCyrillic(string? text) =>
        !string.IsNullOrEmpty(text) && text.Any(c => c is >= '\u0400' and <= '\u04FF');

    /// <summary>
    /// Every title variant the payload carries — original, romaji and the synonym list — as the
    /// candidate array for the AltTitles union. Synonyms joined the blob late: a secondary source
    /// whose spellings all differ is exactly the multi-source "Альт. названия" provenance case.
    /// </summary>
    private static string?[] TitleCandidates(ExternalMediaDto external)
    {
        var candidates = new List<string?> { external.Title, external.OriginalTitle, external.RomajiTitle };
        if (external.Synonyms is { Count: > 0 }) candidates.AddRange(external.Synonyms);
        return [.. candidates];
    }

    /// <summary>
    /// Merges every non-empty title variant (localized, English, Romaji, Native) into the stored
    /// AltTitles blob, minus whatever <paramref name="displayTitle"/> currently shows, so all
    /// language variants stay searchable without ever overwriting the display title.
    /// </summary>
    public static void UpdateAltTitles(MediaItem item, params string?[] candidates)
    {
        // DeserializeAltTitles reads \uXXXX-escaped legacy blobs as well as the relaxed format.
        var merged = new List<string>(DeserializeAltTitles(item.AltTitles));
        foreach (var candidate in candidates.Append(item.Title))
        {
            var value = candidate?.Trim();
            if (string.IsNullOrWhiteSpace(value) || value == item.Title)
            {
                continue;
            }
            if (merged.Contains(value, StringComparer.OrdinalIgnoreCase))
            {
                continue;
            }
            merged.Add(value);
        }

        item.AltTitles = merged.Count > 0 ? SerializeAltTitles(merged) : null;
    }

    /// <summary>
    /// The default JSON encoder escapes every non-ASCII character into \uXXXX, which would bury
    /// Cyrillic and Native titles inside an ASCII-only blob no search could ever match. Alt titles
    /// are stored with relaxed escaping so the raw column text stays human-readable and greppable.
    /// </summary>
    public static string SerializeAltTitles(IReadOnlyList<string> titles) =>
        JsonSerializer.Serialize(titles, AltTitleSerializerOptions);

    public static List<string> DeserializeAltTitles(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json, AltTitleSerializerOptions) ?? [];
        }
        catch
        {
            return [];
        }
    }

    // AOT-safe: the resolver comes from the source-generated context; a bare `new JsonSerializerOptions`
    // falls back to reflection-based serialization, which NativeAOT disables at runtime.
    //
    // Lazy: AppJsonSerializerContext.Default.Options is itself built during static initialization,
    // so reading it from this type's static constructor can deadlock the type initializer chain and
    // surface as TypeInitializationException (NullReferenceException) under NativeAOT. Deferring the
    // read to first use keeps the contexts from initializing each other mid-construction.
    private static readonly Lazy<JsonSerializerOptions> s_altTitleOptions = new(() =>
        new JsonSerializerOptions(AppJsonSerializerContext.Default.Options)
        {
            TypeInfoResolver = AppJsonSerializerContext.Default,
            // The default encoder escapes every non-ASCII character into \uXXXX, which would bury
            // Cyrillic and Native titles inside an ASCII-only blob no search could ever match. Alt
            // titles are stored with relaxed escaping so the raw column text stays readable and greppable.
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        });

    private static JsonSerializerOptions AltTitleSerializerOptions => s_altTitleOptions.Value;

    /// <summary>
    /// Refresh title handling: the display title follows the source, except when the stored one is
    /// a localized (Cyrillic) import and the incoming one is not — a Russian title collected from
    /// Shikimori/Kinopoisk must survive an AniList/MangaDex refresh, and every other variant lands
    /// in the AltTitles blob instead.
    /// </summary>
    public static void ApplyTitle(MediaItem item, ExternalMediaDto external)
    {
        var storedIsRussian = ContainsCyrillic(item.Title);
        var incomingIsRussian = ContainsCyrillic(external.Title);

        if (storedIsRussian && !incomingIsRussian && !string.IsNullOrWhiteSpace(item.Title))
        {
            // Keep the Russian display title; the incoming foreign title joins the alternatives.
            UpdateAltTitles(item, external.Title);
            return;
        }

        item.Title = external.Title;
        UpdateAltTitles(item, TitleCandidates(external));
    }

    /// <summary>
    /// Refresh: external data is authoritative and overwrites whatever is stored.
    /// <paramref name="updateMainCover"/> gates the active poster, not the gallery: a metadata
    /// refresh always appends the source's variant to the gallery, but the poster the user picked
    /// (possibly from another source) stays until they change it — only an explicit re-point of the
    /// primary source brings its own poster forward.
    /// </summary>
    public static async Task ApplyOverwriteAsync(
        MediaItem item,
        ExternalMediaDto external,
        IImageStorageService imageStorage,
        CancellationToken ct,
        Action<TvSeason>? trackNewSeason = null,
        bool fillMissing = true,
        bool updateMainCover = true)
    {
        ApplyTitle(item, external);

        item.Description = external.Description;
        item.TrailerVideoId = external.TrailerVideoId;

        if (IsExternalUrl(external.CoverUrl))
        {
            // The poster a pre-gallery row already has must survive as gallery entry #1 before a
            // variant is appended, or the first refresh would orphan the only copy of it.
            var covers = MediaCoverCollection.EnsureLegacyCoverRegistered(item);

            // A cover from this source already in the gallery.
            var existing = covers.FirstOrDefault(cover =>
                !string.IsNullOrWhiteSpace(cover.Source)
                && string.Equals(cover.Source, external.ExternalSource, StringComparison.OrdinalIgnoreCase));

            if (existing is not null && fillMissing)
            {
                // Enrichment gap-fill: preserve the existing cover, do not re-download.
            }
            else
            {
                // Full refresh (or no existing variant yet): download the new variant first, and
                // only then remove the old same-source variant so a failed download never clears
                // the cover the row already has.
                var variant = await imageStorage.SaveCoverVariantAsync(external.CoverUrl!, item.Id, external.ExternalSource, ct);
                if (variant is not null)
                {
                    // The user's picked poster may BE the variant about to be replaced: its files
                    // are deleted below, so the active pointer must move to the fresh copy — or
                    // the refresh would leave CoverUrl aimed at a deleted file and the card would
                    // render the placeholder while the gallery holds a perfectly good cover.
                    var activeCoverReplaced = false;
                    if (existing is not null)
                    {
                        activeCoverReplaced = MatchesActiveCover(item.CoverUrl, existing);
                        imageStorage.DeleteCoverVariant(item.Id, existing.Id);
                        covers.Remove(existing);
                    }
                    covers.Add(variant);
                    item.CoversJson = MediaCoverCollection.Serialize(covers);

                    // A failed download no longer clears the stored cover either: the gallery only grows.
                    // The active poster follows a freshly downloaded local copy whenever the row has
                    // no local one yet, its current poster is an external hotlink, or the variant it
                    // was pointing at has just been replaced by this download. The user's picked
                    // LOCAL poster survives a routine refresh otherwise.
                    if (updateMainCover
                        || item.CoverUrl is null
                        || IsExternalUrl(item.CoverUrl)
                        || activeCoverReplaced)
                    {
                        item.CoverUrl = variant.ThumbUrl;
                    }
                }
            }
        }
        else if (IsExternalUrl(item.CoverUrl))
        {
            // The source gave no cover this time, but the active poster is an external hotlink
            // while a local variant exists on disk: adopt the local copy, it is the one that
            // actually renders. An existing local poster is never touched.
            var stored = MediaCoverCollection.Parse(item.CoversJson);
            if (stored is { Count: > 0 })
            {
                item.CoverUrl = stored[^1].ThumbUrl;
            }
        }

        // Only written when the source had one: a provider without a creator photo must not erase the
        // one a previous refresh already saved, and the UI falls back to a role icon either way.
        if (IsExternalUrl(external.CreatorImageUrl))
        {
            item.CreatorImageUrl = await imageStorage.SaveCoverAsync(
                external.CreatorImageUrl!,
                item.Id,
                ct,
                "creator");
        }

        // The source the title was added from stays the primary binding: enrichment and refresh
        // merge data across providers, and a merged payload must never re-point ExternalSource at
        // a provider the user did not choose. Only a row with no source yet takes the incoming one.
        item.ExternalId = external.ExternalId;
        item.ExternalSource = string.IsNullOrWhiteSpace(item.ExternalSource)
            ? external.ExternalSource ?? item.ExternalSource
            : item.ExternalSource;
        item.ExternalRating = external.Rating;
        item.ExternalRatingVotes = external.RatingVotes;
        item.OriginalLanguage = external.OriginalLanguage;
        item.CountryOfOrigin = external.CountryOfOrigin;
        item.CastJson = external.Cast is { Count: > 0 } cast ? JsonSerializer.Serialize(cast, AppJsonSerializerContext.Default.IReadOnlyListCastMemberDto) : null;
        item.OriginalTitle = external.OriginalTitle;
        UpdateAltTitles(item, TitleCandidates(external));
        item.StaffJson = external.Staff is { Count: > 0 } staff ? JsonSerializer.Serialize(staff, AppJsonSerializerContext.Default.IReadOnlyListExternalStaffMemberDto) : null;

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
        UpdateAltTitles(item, TitleCandidates(external));
        modified |= SetIfBlank(item.OriginalLanguage, external.OriginalLanguage, value => item.OriginalLanguage = value);
        modified |= SetIfBlank(item.CountryOfOrigin, external.CountryOfOrigin, value => item.CountryOfOrigin = value);
        if (string.IsNullOrWhiteSpace(item.CastJson) && external.Cast is { Count: > 0 } cast)
        {
            item.CastJson = JsonSerializer.Serialize(cast, AppJsonSerializerContext.Default.IReadOnlyListCastMemberDto);
            modified = true;
        }
        modified |= SetIfBlank(item.OriginalTitle, external.OriginalTitle, value => item.OriginalTitle = value);
        modified |= SetIfBlank(item.StaffJson, external.Staff is { Count: > 0 } staff
            ? JsonSerializer.Serialize(staff, AppJsonSerializerContext.Default.IReadOnlyListExternalStaffMemberDto)
            : null, value => item.StaffJson = value);
        modified |= ApplyMangaGaps(item, external);

        modified |= SetIfBlank(item.Description, external.Description, value => item.Description = value);
        modified |= SetIfBlank(item.TrailerVideoId, external.TrailerVideoId, value => item.TrailerVideoId = value);
        // No image storage on this path, so external URLs are skipped and MUST be saved by the next full refresh.
        if (!IsExternalUrl(external.CreatorImageUrl))
        {
            modified |= SetIfBlank(item.CreatorImageUrl, external.CreatorImageUrl, value => item.CreatorImageUrl = value);
        }
        modified |= SetIfBlank(item.Genres, JoinGenres(external.Genres), value => item.Genres = value);
        modified |= ApplyDisplayGaps(item, external, trackNewSeason);

        // Runs last: deriving the status from dates is only correct once the dates themselves are in.
        if (string.IsNullOrWhiteSpace(item.ReleaseStatus))
        {
            var status = ReleaseStatusRules.NormalizeStatus(
                !string.IsNullOrWhiteSpace(external.ReleaseStatus)
                    ? external.ReleaseStatus
                    // No source declared a status, but a past end date or a future start date still
                    // decides it, and the row would otherwise stay empty.
                    : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate));

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
                modified |= SetIfBlank(movie.Director, external.Director ?? external.Author, value => movie.Director = value);
                modified |= SetIfBlank(movie.RomajiTitle, external.RomajiTitle ?? external.OriginalTitle, value => movie.RomajiTitle = value);
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
                var isClassicBook = MediaMerger.IsClassicBook(item);

                if (!isClassicBook && book.Format is null && (external.MangaFormat is not null || external.Format is not null))
                {
                    var fmt = external.MangaFormat ?? external.Format;
                    if (fmt is "light_novel" or "web_novel" or "novel")
                    {
                        book.Format = fmt == "novel" ? "light_novel" : fmt;
                        modified = true;
                    }
                }

                if (book.Format is "light_novel" or "web_novel")
                {
                    if (book.TotalChapters is null or <= 0 && (external.Chapters is > 0 || external.TotalCount is > 0))
                    {
                        book.TotalChapters = external.Chapters is > 0 ? external.Chapters.Value : external.TotalCount!.Value;
                        modified = true;
                    }
                    if (book.TotalVolumes is null or <= 0 && external.Volumes is > 0)
                    {
                        book.TotalVolumes = external.Volumes.Value;
                        modified = true;
                    }
                }
                else
                {
                    if (book.TotalPages <= 0 && external.TotalCount is > 0)
                    {
                        book.TotalPages = external.TotalCount.Value;
                        modified = true;
                    }
                }

                modified |= SetIfBlank(book.Author, external.Author, value => book.Author = value);
                break;

            case VideoGame game:
                // Steam and RAWG both report the developers; without this branch enrichment threw
                // the list away and the overview's "Разработчик" card had nothing to render.
                modified |= SetIfBlank(game.Studio, external.Studio, value => game.Studio = value);
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
            episodes is null ? null : JsonSerializer.Serialize(episodes, AppJsonSerializerContext.Default.IReadOnlyListExternalEpisodeDto),
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
        ExternalMediaDto external)
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

        return modified;
    }

    private static void ApplyDates(MediaItem item, ExternalMediaDto external)
    {
        // "2021" / "2021-03" mean the source only knows that much; inventing Jan 1 for the missing
        // part is the lie behind "1 January 2021", so the date stays unset and the year is stored raw.
        item.SetReleaseDate(ParseDate(external.ReleaseDate), external.ReleaseYear);
        item.EndDate = ParseDate(external.EndDate);

        // Every stored status goes through the canonical fold, whatever the source called it.
        item.ReleaseStatus = ReleaseStatusRules.NormalizeStatus(
            !string.IsNullOrWhiteSpace(external.ReleaseStatus)
                ? external.ReleaseStatus
                : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate));
    }

    private static void ApplyGenres(MediaItem item, ExternalMediaDto external)
    {
        if (external.Genres is { Count: > 0 })
        {
            item.Genres = GenreNormalizer.NormalizeToCommaString(external.Genres);
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
                var movieRomaji = external.RomajiTitle ?? external.OriginalTitle;
                if (!string.IsNullOrWhiteSpace(movieRomaji)) movie.RomajiTitle = movieRomaji;
                if (!string.IsNullOrWhiteSpace(external.Director)) movie.Director = external.Director;
                else if (!string.IsNullOrWhiteSpace(external.Author)) movie.Director = external.Author;
                break;
            case Book book:
                var isClassic = MediaMerger.IsClassicBook(item);

                if (!isClassic && (external.MangaFormat is not null || external.Format is not null))
                {
                    var fmt = external.MangaFormat ?? external.Format;
                    if (fmt is "light_novel" or "web_novel" or "novel" or "book")
                    {
                        book.Format = fmt == "novel" ? "light_novel" : fmt;
                    }
                }
                if (book.Format is "light_novel" or "web_novel")
                {
                    if (external.Chapters is > 0) book.TotalChapters = external.Chapters.Value;
                    else if (external.TotalCount is > 0) book.TotalChapters = external.TotalCount.Value;
                    if (external.Volumes is > 0) book.TotalVolumes = external.Volumes.Value;
                }
                else if (external.TotalCount is > 0)
                {
                    book.TotalPages = external.TotalCount.Value;
                }
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
                if (!string.IsNullOrWhiteSpace(external.Studio)) game.Studio = external.Studio;
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

        var showRomaji = external.RomajiTitle ?? external.OriginalTitle;
        if (!string.IsNullOrWhiteSpace(showRomaji))
        {
            show.RomajiTitle = showRomaji;
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
        var episodesJson = JsonSerializer.Serialize(episodes, AppJsonSerializerContext.Default.IReadOnlyListExternalEpisodeDto);

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
                ? JsonSerializer.Serialize(list, AppJsonSerializerContext.Default.IReadOnlyListExternalEpisodeDto)
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

    private static DateTime? ParseDate(string? value) =>
        DateTime.TryParse(value, out var parsed) ? parsed : null;

    private static string? JoinGenres(IReadOnlyList<string>? genres) =>
        GenreNormalizer.NormalizeToCommaString(genres);

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
