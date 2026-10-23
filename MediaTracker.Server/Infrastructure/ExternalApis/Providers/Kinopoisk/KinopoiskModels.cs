using System.Net.Http.Json;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json.Serialization;
using MediaTracker.Server.Common.Utilities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed class KinopoiskSearchResponse
{
    [JsonPropertyName("films")]
    public List<KinopoiskFilmItem>? Films { get; set; }
}

internal sealed class KinopoiskFilmItem
{
    [JsonPropertyName("filmId")]
    public long FilmId { get; set; }

    /// <summary>FILM | VIDEO | TV_SERIES | MINI_SERIES | TV_SHOW — the type the source declares.</summary>
    [JsonPropertyName("type")]
    public string? Type { get; set; }

    [JsonPropertyName("filmLength")]
    public string? FilmLength { get; set; }

    [JsonPropertyName("genres")]
    public List<KinopoiskGenre>? Genres { get; set; }

    [JsonPropertyName("nameRu")]
    public string? NameRu { get; set; }

    [JsonPropertyName("nameEn")]
    public string? NameEn { get; set; }

    [JsonPropertyName("year")]
    public string? Year { get; set; }

    [JsonPropertyName("rating")]
    public string? Rating { get; set; }

    [JsonPropertyName("ratingVoteCount")]
    public int? RatingVoteCount { get; set; }

    [JsonPropertyName("posterUrl")]
    public string? PosterUrl { get; set; }

    [JsonPropertyName("posterUrlPreview")]
    public string? PosterUrlPreview { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }
}

internal sealed class KinopoiskDetailItem
{
    [JsonPropertyName("kinopoiskId")]
    public long KinopoiskId { get; set; }

    [JsonPropertyName("nameRu")]
    public string? NameRu { get; set; }

    [JsonPropertyName("nameEn")]
    public string? NameEn { get; set; }

    [JsonPropertyName("nameOriginal")]
    public string? NameOriginal { get; set; }

    [JsonPropertyName("posterUrl")]
    public string? PosterUrl { get; set; }

    [JsonPropertyName("posterUrlPreview")]
    public string? PosterUrlPreview { get; set; }

    [JsonPropertyName("ratingKinopoisk")]
    public double? RatingKinopoisk { get; set; }

    [JsonPropertyName("ratingKinopoiskVoteCount")]
    public int? RatingKinopoiskVoteCount { get; set; }

    [JsonPropertyName("ratingImdb")]
    public double? RatingImdb { get; set; }

    [JsonPropertyName("ratingImdbVoteCount")]
    public int? RatingImdbVoteCount { get; set; }

    /// <summary>Average episode runtime of a series, in minutes.</summary>
    [JsonPropertyName("seriesLength")]
    public int? SeriesLength { get; set; }

    /// <summary>Production companies / networks; the studio or network a title belongs to.</summary>
    [JsonPropertyName("productionCompanies")]
    public List<KinopoiskCompany>? ProductionCompanies { get; set; }

    [JsonPropertyName("year")]
    public int? Year { get; set; }

    /// <summary>Premier year. Set for series where <c>year</c> can lag behind.</summary>
    [JsonPropertyName("startYear")]
    public int? StartYear { get; set; }

    /// <summary>Final year. Null while the series is still running.</summary>
    [JsonPropertyName("endYear")]
    public int? EndYear { get; set; }

    /// <summary>Runtime of a film, or the average episode runtime of a series.</summary>
    [JsonPropertyName("filmLength")]
    public int? FilmLength { get; set; }

    /// <summary>FILMING | PRE_PRODUCTION | COMPLETED | ANNOUNCED | UNKNOWN | POST_PRODUCTION.</summary>
    [JsonPropertyName("productionStatus")]
    public string? ProductionStatus { get; set; }

    /// <summary>Whether the whole series has finished airing.</summary>
    [JsonPropertyName("completed")]
    public bool? Completed { get; set; }

    [JsonPropertyName("genres")]
    public List<KinopoiskGenre>? Genres { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }
}

internal sealed class KinopoiskGenre
{
    [JsonPropertyName("genre")]
    public string? Genre { get; set; }
}

internal sealed class KinopoiskCompany
{
    [JsonPropertyName("name")]
    public string? Name { get; set; }
}

internal sealed class KinopoiskStaffMember
{
    [System.Text.Json.Serialization.JsonPropertyName("nameRu")]
    public string? NameRu { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("nameEn")]
    public string? NameEn { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("professionKey")]
    public string? ProfessionKey { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("description")]
    public string? Description { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("posterUrl")]
    public string? PosterUrl { get; set; }
}

internal sealed class KinopoiskVideosResponse
{
    [System.Text.Json.Serialization.JsonPropertyName("total")]
    public int? Total { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("items")]
    public List<KinopoiskVideoItem>? Items { get; set; }
}

internal sealed class KinopoiskVideoItem
{
    [System.Text.Json.Serialization.JsonPropertyName("url")]
    public string? Url { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("name")]
    public string? Name { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("site")]
    public string? Site { get; set; }
}

internal sealed class KinopoiskSeasonsResponse
{
    [JsonPropertyName("total")]
    public int? Total { get; set; }

    [JsonPropertyName("items")]
    public List<KinopoiskSeason>? Items { get; set; }
}

internal sealed class KinopoiskSeason
{
    [JsonPropertyName("number")]
    public int Number { get; set; }

    [JsonPropertyName("episodes")]
    public List<KinopoiskEpisode>? Episodes { get; set; }
}

internal sealed class KinopoiskEpisode
{
    [JsonPropertyName("seasonNumber")]
    public int? SeasonNumber { get; set; }

    [JsonPropertyName("episodeNumber")]
    public int? EpisodeNumber { get; set; }

    [JsonPropertyName("nameRu")]
    public string? NameRu { get; set; }

    [JsonPropertyName("nameEn")]
    public string? NameEn { get; set; }

    [JsonPropertyName("releaseDate")]
    public string? ReleaseDate { get; set; }
}
