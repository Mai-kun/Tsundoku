using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class TmdbMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<TmdbMetadataProvider> logger,
    [ServiceKey] string? serviceKey = null) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "tmdb",
        Name: "The Movie Database (TMDb)",
        Description: "Movies and TV Shows metadata & ratings provider",
        MediaTypes: ["movie", "tvshow"],
        BaseAddress: "https://api.themoviedb.org/3/",
        RequiresApiKey: true,
        IsDefault: true,
        Priority: 1,
        // Ratings show the short brand, the settings label keeps the full title.
        CanonicalName: "TMDB",
        Aliases: ["movie database"]);

    private readonly string mediaType = serviceKey?.StartsWith("movie", StringComparison.OrdinalIgnoreCase) is true ? "movie" : "tvshow";

    /// <summary>Real endpoint probe: a missing or rejected key used to read as "reachable in 0 ms".</summary>
    public override async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var apiKey = options.Value.TmdbApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return new ConnectionTestResult(false, 0, "API-ключ TMDb не указан");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(5));
            using var resp = await client.GetAsync(
                $"configuration?api_key={Uri.EscapeDataString(apiKey)}",
                HttpCompletionOption.ResponseHeadersRead, timeoutCts.Token);
            sw.Stop();

            if (resp.IsSuccessStatusCode)
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            if (resp.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Недействительный API-ключ TMDb");
            }

            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds,
                $"TMDb вернул HTTP {(int)resp.StatusCode} ({resp.ReasonPhrase})");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, "Таймаут — TMDb не отвечает");
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var apiKey = options.Value.TmdbApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            logger.LogWarning("TMDB API key is not configured, external search returns no results");
            return [];
        }

        var client = httpClientFactory.CreateClient(Id);
        var isMovie = mediaType == "movie";
        var searchPath = isMovie ? "search/movie" : "search/tv";

        try
        {
            var result = await client.GetFromJsonAsync<TmdbResponse>(
                $"{searchPath}?query={Uri.EscapeDataString(query)}&api_key={Uri.EscapeDataString(apiKey)}", ct);

            if (result?.Results is not { Count: > 0 } results)
            {
                return [];
            }

            return [.. results
                .Where(item => isMovie ? item.Title is not null : item.Name is not null)
                .Select(MapItem)];
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to search TMDB for {Query}", query);
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var apiKey = options.Value.TmdbApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return null;
        }

        if (long.TryParse(externalId, out var id))
        {
            try
            {
                var client = httpClientFactory.CreateClient(Id);
                var isMovie = mediaType == "movie";
                var detailPath = isMovie ? $"movie/{id}" : $"tv/{id}";
                var item = await client.GetFromJsonAsync<TmdbItem>(
                    $"{detailPath}?api_key={Uri.EscapeDataString(apiKey)}&append_to_response=credits,videos", ct);

                if (item is not null)
                {
                    return MapItem(item);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to get TMDB details for {Id}", externalId);
                throw;
            }
        }

        var searchResults = await SearchAsync(title, ct);
        return searchResults.Count > 0 ? searchResults[0] : null;
    }

    private ExternalMediaDto MapItem(TmdbItem item)
    {
        var isMovie = mediaType == "movie";
        var rating = item.VoteAverage is { } va && va > 0 ? Math.Round(va, 1) : (double?)null;
        var ratings = rating is not null
            ? new List<ExternalRatingDto>
            {
                new() { Source = "TMDB", Rating = rating.Value, Votes = item.VoteCount }
            }
            : null;

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(),
            ExternalSource = "TMDB",
            Title = isMovie ? item.Title ?? string.Empty : item.Name ?? string.Empty,
            OriginalTitle = isMovie ? item.OriginalTitle : item.OriginalName,
            CoverUrl = item.PosterPath is null ? null : $"https://image.tmdb.org/t/p/w500{item.PosterPath}",
            Description = item.Overview,
            TrailerVideoId = item.Videos?.Results?
                .FirstOrDefault(video => string.Equals(video.Site, "YouTube", StringComparison.OrdinalIgnoreCase)
                    && string.Equals(video.Type, "Trailer", StringComparison.OrdinalIgnoreCase))?.Key
                ?? item.Videos?.Results?
                    .FirstOrDefault(video => string.Equals(video.Site, "YouTube", StringComparison.OrdinalIgnoreCase)
                        && string.Equals(video.Type, "Teaser", StringComparison.OrdinalIgnoreCase))?.Key,
            ReleaseYear = ParseYear(isMovie ? item.ReleaseDate : item.FirstAirDate),
            ReleaseDate = isMovie ? item.ReleaseDate : item.FirstAirDate,
            // `last_air_date` is the mirror of `first_air_date` and is null while a series still airs.
            // It was never mapped, so the end-date row was empty for every TMDb-sourced show.
            EndDate = isMovie ? null : item.LastAirDate,
            ReleaseStatus = item.Status,
            OriginalLanguage = item.OriginalLanguage,
            // Movies carry a runtime, series only an average per-episode one; both live in `runtime`.
            RuntimeMinutes = item.Runtime,
            // TMDb returns the production companies but the provider never mapped them, so the studio
            // field stayed empty even though the source had the data all along.
            Studio = isMovie
                ? item.ProductionCompanies?.FirstOrDefault(c => !string.IsNullOrWhiteSpace(c.Name))?.Name
                : item.Networks?.FirstOrDefault(n => !string.IsNullOrWhiteSpace(n.Name))?.Name,
            Type = mediaType,
            Rating = rating,
            RatingVotes = item.VoteCount,
            Ratings = ratings,
            Genres = item.Genres is { Count: > 0 } genres
                ? [.. genres.Select(genre => genre.Name).OfType<string>()]
                : null,
            TotalCount = isMovie ? item.Runtime : item.NumberOfEpisodes,
            Cast = item.Credits?.Cast?
                .Where(cast => !string.IsNullOrWhiteSpace(cast.Name))
                .Take(6)
                .Select(cast => new CastMemberDto(
                    cast.Name!,
                    cast.Character,
                    ImageUrl(cast.ProfilePath, "w185")))
                .ToList(),
            Director = isMovie
                ? item.Credits?.Crew?
                    .FirstOrDefault(c => string.Equals(c.Job, "Director", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(c.Name))?.Name
                : null,
            CreatorImageUrl = isMovie
                ? ImageUrl(
                    item.Credits?.Crew?
                        .FirstOrDefault(crew => string.Equals(crew.Job, "Director", StringComparison.OrdinalIgnoreCase)
                            && !string.IsNullOrWhiteSpace(crew.ProfilePath))
                        ?.ProfilePath,
                    "w185")
                : StudioLogoUrl(item)
        };
    }

    private static string? ImageUrl(string? path, string size) =>
        string.IsNullOrWhiteSpace(path) ? null : $"https://image.tmdb.org/t/p/{size}{path}";

    /// <summary>
    /// A series card names the network, and TMDb's networks carry no logo, so the production company's
    /// logo is only used when it is the very studio on the card. Pairing a logo with a different name
    /// would be a picture of the wrong thing.
    /// </summary>
    private static string? StudioLogoUrl(TmdbItem item)
    {
        var studio = item.Networks?.FirstOrDefault(n => !string.IsNullOrWhiteSpace(n.Name))?.Name;
        var company = item.ProductionCompanies?.FirstOrDefault(c => !string.IsNullOrWhiteSpace(c.LogoPath));
        return company is not null && string.Equals(company.Name, studio, StringComparison.OrdinalIgnoreCase)
            ? ImageUrl(company.LogoPath, "w185")
            : null;
    }

    private static int? ParseYear(string? date) =>
        date is { Length: >= 4 } && int.TryParse(date[..4], out var year) ? year : null;
}
