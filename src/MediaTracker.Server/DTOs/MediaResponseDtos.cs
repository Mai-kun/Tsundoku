using System.Diagnostics.CodeAnalysis;
using MediaTracker.Server.Models;

namespace MediaTracker.Server.DTOs;

public record MediaListDto
{
    public required Guid Id { get; init; }

    public required string Type { get; init; }

    public required string Title { get; init; }

    public required MediaStatus Status { get; init; }

    public int? Score { get; init; }

    public DateTime? StartedAt { get; init; }

    public DateTime? FinishedAt { get; init; }

    public string? Notes { get; init; }

    public string? CoverUrl { get; init; }

    public required DateTime CreatedAt { get; init; }

    public Guid? FranchiseId { get; init; }

    public int? FranchiseOrder { get; init; }

    public string? Platform { get; init; }

    public int? HoursPlayed { get; init; }

    public string? Author { get; init; }

    public int? CurrentPage { get; init; }

    public int? TotalPages { get; init; }

    public int? CurrentChapter { get; init; }

    public int? TotalChapters { get; init; }

    public int? CurrentVolume { get; init; }

    public int? DurationMinutes { get; init; }

    public string? Director { get; init; }

    public bool? IsAnime { get; init; }

    public string? Studio { get; init; }

    public string? RomajiTitle { get; init; }

    public string? Network { get; init; }

    public int? TotalEpisodesCount { get; init; }

    public int? TotalEpisodesWatched { get; init; }

    public int? SeasonsCount { get; init; }
}

public sealed record MediaDetailDto : MediaListDto
{
    [SetsRequiredMembers]
    public MediaDetailDto(MediaListDto source) : base(source)
    {
    }

    public IReadOnlyList<TvSeasonDto>? Seasons { get; init; }
}

public sealed record TvSeasonDto
{
    public required Guid Id { get; init; }

    public required int SeasonNumber { get; init; }

    public required string Title { get; init; }

    public string? CoverUrl { get; init; }

    public required int CurrentEpisode { get; init; }

    public required int TotalEpisodes { get; init; }

    public required MediaStatus Status { get; init; }

    public int? Score { get; init; }

    public string? Notes { get; init; }

    public DateTime? AirDate { get; init; }

    public required Guid TvShowId { get; init; }
}

public static class MediaResponseMapper
{
    public static MediaListDto ToListDto(MediaItem item)
    {
        var dto = CreateBaseDto(item, GetType(item));

        return item switch
        {
            VideoGame game => dto with
            {
                Platform = game.Platform,
                HoursPlayed = game.HoursPlayed,
            },
            Book book => dto with
            {
                Author = book.Author,
                CurrentPage = book.CurrentPage,
                TotalPages = book.TotalPages,
            },
            Manga manga => dto with
            {
                CurrentChapter = manga.CurrentChapter,
                TotalChapters = manga.TotalChapters,
                CurrentVolume = manga.CurrentVolume,
            },
            Movie movie => dto with
            {
                DurationMinutes = movie.DurationMinutes,
                Director = movie.Director,
                IsAnime = movie.IsAnime,
                Studio = movie.Studio,
                RomajiTitle = movie.RomajiTitle,
            },
            TvShow show => dto with
            {
                IsAnime = show.IsAnime,
                Studio = show.Studio,
                RomajiTitle = show.RomajiTitle,
                Network = show.Network,
                TotalEpisodesCount = show.TotalEpisodesCount,
                TotalEpisodesWatched = show.TotalEpisodesWatched,
                SeasonsCount = show.Seasons.Count,
            },
            _ => throw new InvalidOperationException($"Unsupported media item '{item.GetType().Name}'."),
        };
    }

    public static MediaDetailDto ToDetailDto(MediaItem item)
    {
        var detail = new MediaDetailDto(ToListDto(item));

        return item is TvShow show
            ? detail with
            {
                Seasons = show.Seasons
                    .OrderBy(season => season.SeasonNumber)
                    .Select(ToDto)
                    .ToArray(),
            }
            : detail;
    }

    private static MediaListDto CreateBaseDto(MediaItem item, string type) => new()
    {
        Id = item.Id,
        Type = type,
        Title = item.Title,
        Status = item.Status,
        Score = item.Score,
        StartedAt = item.StartedAt,
        FinishedAt = item.FinishedAt,
        Notes = item.Notes,
        CoverUrl = item.CoverUrl,
        CreatedAt = item.CreatedAt,
        FranchiseId = item.FranchiseId,
        FranchiseOrder = item.FranchiseOrder,
    };

    private static string GetType(MediaItem item) => item switch
    {
        VideoGame => "game",
        Book => "book",
        Manga => "manga",
        Movie => "movie",
        TvShow => "tvshow",
        _ => throw new InvalidOperationException($"Unsupported media item '{item.GetType().Name}'."),
    };

    private static TvSeasonDto ToDto(TvSeason season) => new()
    {
        Id = season.Id,
        SeasonNumber = season.SeasonNumber,
        Title = season.Title,
        CoverUrl = season.CoverUrl,
        CurrentEpisode = season.CurrentEpisode,
        TotalEpisodes = season.TotalEpisodes,
        Status = season.Status,
        Score = season.Score,
        Notes = season.Notes,
        AirDate = season.AirDate,
        TvShowId = season.TvShowId,
    };
}
