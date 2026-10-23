using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

internal sealed record TmdbResponse(List<TmdbItem>? Results);

internal sealed record TmdbItem(
    long Id,
    string? Title,
    [property: JsonPropertyName("original_title")] string? OriginalTitle,
    string? Name,
    [property: JsonPropertyName("original_name")] string? OriginalName,
    string? Overview,
    [property: JsonPropertyName("poster_path")] string? PosterPath,
    [property: JsonPropertyName("release_date")] string? ReleaseDate,
    [property: JsonPropertyName("first_air_date")] string? FirstAirDate,
    [property: JsonPropertyName("last_air_date")] string? LastAirDate,
    [property: JsonPropertyName("vote_average")] double? VoteAverage,
    [property: JsonPropertyName("vote_count")] int? VoteCount,
    [property: JsonPropertyName("runtime")] int? Runtime,
    [property: JsonPropertyName("number_of_episodes")] int? NumberOfEpisodes,
    [property: JsonPropertyName("status")] string? Status,
    [property: JsonPropertyName("production_companies")] List<TmdbNamedItem>? ProductionCompanies,
    [property: JsonPropertyName("networks")] List<TmdbNamedItem>? Networks,
    [property: JsonPropertyName("genres")] List<TmdbNamedItem>? Genres,
    [property: JsonPropertyName("original_language")] string? OriginalLanguage,
    [property: JsonPropertyName("credits")] TmdbCredits? Credits,
    [property: JsonPropertyName("videos")] TmdbVideos? Videos);

internal sealed record TmdbVideos([property: JsonPropertyName("results")] List<TmdbVideo>? Results);

internal sealed record TmdbVideo(string? Site, string? Type, string? Key);

internal sealed record TmdbCredits(
    [property: JsonPropertyName("cast")] List<TmdbCastMember>? Cast,
    [property: JsonPropertyName("crew")] List<TmdbCrewMember>? Crew);

internal sealed record TmdbCrewMember(
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("job")] string? Job,
    [property: JsonPropertyName("profile_path")] string? ProfilePath);

internal sealed record TmdbCastMember(
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("character")] string? Character,
    [property: JsonPropertyName("profile_path")] string? ProfilePath);

internal sealed record TmdbNamedItem(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("logo_path")] string? LogoPath);

internal sealed class TmdbPage
{
    public List<TmdbRelationItem>? Results { get; set; }
}

internal sealed class TmdbRelationItem
{
    [JsonPropertyName("id")]
    public long? Id { get; set; }

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("poster_path")]
    public string? PosterPath { get; set; }

    [JsonPropertyName("release_date")]
    public string? ReleaseDate { get; set; }

    [JsonPropertyName("first_air_date")]
    public string? FirstAirDate { get; set; }

    [JsonPropertyName("vote_average")]
    public double? VoteAverage { get; set; }

    /// <summary>Films spell it "title", series spell it "name"; the mapper reads whichever is set.</summary>
    public string? Name { get; set; }

}
