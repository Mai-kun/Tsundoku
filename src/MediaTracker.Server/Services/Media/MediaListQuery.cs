using System.Collections.Frozen;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Services.Media;

/// <summary>
/// Filters, ordering and the DTO projection for the media list endpoint, expressed once so the
/// handler stays thin. The projection keeps the read in a single SQL statement: no TPH entity graph
/// is materialized and the season/volume collections are reduced to aggregates by the database.
/// </summary>
public static class MediaListQuery
{
    private const string Discriminator = "MediaType";

    private static readonly FrozenDictionary<string, string> TypeToDiscriminator =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["game"] = "Game",
            ["book"] = "Book",
            ["manga"] = "Manga",
            ["movie"] = "Movie",
            ["tvshow"] = "TvShow",
        }.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);

    /// <summary>Returns false when the requested type is unknown — the caller answers with an empty list.</summary>
    public static bool TryBuild(
        AppDbContext db,
        string? type,
        MediaStatus? status,
        bool? isAnime,
        string? search,
        string? sortBy,
        string? sortOrder,
        out IQueryable<MediaListRow> query)
    {
        query = default!;

        var trimmedType = type?.Trim();

        if (!string.IsNullOrEmpty(trimmedType) && !TypeToDiscriminator.ContainsKey(trimmedType))
        {
            return false;
        }

        var source = db.MediaItems.AsNoTracking();

        if (trimmedType is { } discriminatorKey)
        {
            var discriminator = TypeToDiscriminator[discriminatorKey];
            source = source.Where(item => EF.Property<string>(item, Discriminator) == discriminator);
        }

        if (status is { } statusFilter)
        {
            source = source.Where(item => item.Status == statusFilter);
        }

        if (isAnime is { } animeFilter)
        {
            source = source.Where(item =>
                (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).IsAnime == animeFilter)
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).IsAnime == animeFilter));
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            source = ApplySearchTerm(source, search.Trim());
        }

        source = ApplyOrdering(source, sortBy, sortOrder);

        query = ProjectListRows(source);
        return true;
    }

    /// <summary>
    /// One list row: the projected DTO plus the raw update timestamp the cover cache-buster is
    /// derived from. Ticks is not SQL-translatable, so the version string is stamped in memory.
    /// </summary>
    public sealed record MediaListRow(MediaListDto Item, DateTime UpdatedAt);

    private static IQueryable<MediaListRow> ProjectListRows(IQueryable<MediaItem> source) =>
        source.Select(item => new MediaListRow(
            new MediaListDto
            {
                Id = item.Id,
                Type = item is VideoGame ? "game"
                    : item is Book ? "book"
                    : item is Manga ? "manga"
                    : item is Movie ? "movie"
                    : "tvshow",
                Title = item.Title,
                Status = item.Status,
                Score = item.Score,
                StartedAt = item.StartedAt,
                FinishedAt = item.FinishedAt,
                ReleaseDate = item.ReleaseDate,
                ReleaseYear = item.ReleaseYear,
                WatchedOn = item.WatchedOn,
                EndDate = item.EndDate,
                ReleaseStatus = item.ReleaseStatus,
                Notes = item.Notes,
                CoverUrl = item.CoverUrl,
                CreatedAt = item.CreatedAt,
                FranchiseId = item.FranchiseId,
                FranchiseName = item.Franchise != null ? item.Franchise.Name : null,
                FranchiseOrder = item.FranchiseOrder,
                Platform = item is VideoGame ? ((VideoGame)item).Platform : null,
                HoursPlayed = item is VideoGame ? ((VideoGame)item).HoursPlayed : null,
                Author = item is Book ? ((Book)item).Author : item is Manga ? ((Manga)item).Author : null,
                CurrentPage = item is Book ? ((Book)item).CurrentPage : null,
                TotalPages = item is Book
                    ? ((Book)item).TotalPages
                    : item is Manga
                        ? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Sum(volume => volume.TotalPages) : null)
                        : null,
                CurrentChapter = item is Manga ? ((Manga)item).CurrentChapter : null,
                TotalChapters = item is Manga
                    ? (((Manga)item).TotalChapters
                        ?? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Sum(volume => volume.TotalChapters) : null))
                    : null,
                CurrentVolume = item is Manga ? ((Manga)item).CurrentVolume : null,
                TotalVolumes = item is Manga
                    ? (((Manga)item).TotalVolumes
                        ?? (((Manga)item).Volumes.Count > 0 ? ((Manga)item).Volumes.Count : null))
                    : null,
                DurationMinutes = item is Movie
                    ? ((Movie)item).DurationMinutes
                    : item is TvShow
                        ? ((TvShow)item).EpisodeDurationMinutes
                        : null,
                Director = item is Movie ? ((Movie)item).Director : null,
                IsAnime = item is Movie ? ((Movie)item).IsAnime : item is TvShow ? ((TvShow)item).IsAnime : null,
                Studio = item is Movie ? ((Movie)item).Studio : item is TvShow ? ((TvShow)item).Studio : null,
                RomajiTitle = item is Movie
                    ? ((Movie)item).RomajiTitle
                    : item is TvShow
                        ? ((TvShow)item).RomajiTitle
                        : item is Manga ? ((Manga)item).RomajiTitle : null,
                Network = item is TvShow ? ((TvShow)item).Network : null,
                TotalEpisodesCount = item is TvShow ? ((TvShow)item).Seasons.Sum(season => season.TotalEpisodes) : null,
                TotalEpisodesWatched = item is TvShow ? ((TvShow)item).Seasons.Sum(season => season.CurrentEpisode) : null,
                SeasonsCount = item is TvShow ? ((TvShow)item).Seasons.Count : 0,
                ExternalId = item.ExternalId,
                ExternalSource = item.ExternalSource,
                ExternalRating = item.ExternalRating,
                ExternalRatingVotes = item.ExternalRatingVotes,
                ExternalRatingsJson = item.ExternalRatingsJson,
                TranslatedSynopsis = item.TranslatedSynopsis,
                TranslationLanguage = item.TranslationLanguage,
                Genres = item.Genres,
                Tags = item.Tags,
                UnlockedAchievements = item.UnlockedAchievements,
                UserPlatform = item.UserPlatform,
            },
            item.UpdatedAt));

    private static IQueryable<MediaItem> ApplySearchTerm(IQueryable<MediaItem> query, string term)
    {
        var pattern = $"%{term}%";
        return query.Where(item =>
            EF.Functions.Like(item.Title, pattern)
            || (item.Franchise != null && EF.Functions.Like(item.Franchise.Name, pattern))
            || (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).RomajiTitle != null && EF.Functions.Like(((Movie)item).RomajiTitle, pattern))
            || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).RomajiTitle != null && EF.Functions.Like(((TvShow)item).RomajiTitle, pattern)));
    }

    private static IQueryable<MediaItem> ApplyOrdering(IQueryable<MediaItem> query, string? sortBy, string? sortOrder)
    {
        var isAscending = string.Equals(sortOrder, "asc", StringComparison.OrdinalIgnoreCase);
        var trimmedSort = sortBy?.Trim();

        if (string.Equals(trimmedSort, "score", StringComparison.OrdinalIgnoreCase))
        {
            return isAscending
                ? query.OrderBy(item => item.Score == null).ThenBy(item => item.Score)
                : query.OrderBy(item => item.Score == null).ThenByDescending(item => item.Score);
        }

        if (string.Equals(trimmedSort, "title", StringComparison.OrdinalIgnoreCase))
        {
            return isAscending
                ? query.OrderBy(item => item.Title)
                : query.OrderByDescending(item => item.Title);
        }

        return isAscending
            ? query.OrderBy(item => item.CreatedAt)
            : query.OrderByDescending(item => item.CreatedAt);
    }
}
