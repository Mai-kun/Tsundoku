using System.Diagnostics;
using System.Globalization;
using System.Text.Json.Serialization;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed class KinopoiskMetadataProvider(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    [ServiceKey] string? serviceKey = null
) : MetadataProviderBase
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "kinopoisk",
        Name: "Кинопоиск (Kinopoisk)",
        Description: "Russian and international movies, TV series metadata & ratings",
        MediaTypes: ["movie", "tvshow"],
        BaseAddress: "https://kinopoiskapiunofficial.tech/api/",
        RequiresApiKey: true,
        Priority: 3);

    private readonly string _mediaType = serviceKey?.StartsWith(
        "tvshow",
        StringComparison.OrdinalIgnoreCase
    )
        is true
        ? "tvshow"
        : "movie";
    private string ApiKey => options.Value.GetKey(Id) ?? string.Empty;

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(
        string query,
        CancellationToken ct
    )
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
            return [];

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"v2.1/films/search-by-keyword?keyword={Uri.EscapeDataString(query)}&page=1";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
                return [];

            var body = await resp.Content.ReadFromJsonAsync<KinopoiskSearchResponse>(ct);
            if (body?.Films is null || body.Films.Count == 0)
                return [];

            // search-by-keyword returns films *and* series mixed together. Mapping the whole list to the
            // configured type is what put a movie into the "TV Shows" group, so the source is asked for
            // the wanted type first and the declared type is re-checked afterwards.
            var expectedType = _mediaType == "movie" ? "movie" : "tv";
            var matching = body.Films.Where(film => MatchesType(film.Type, expectedType)).ToList();

            // Never return nothing just because the filter was stricter than this source's labels: an
            // empty list makes the aggregator move on and the source silently disappears from search.
            if (matching.Count == 0)
            {
                matching = body.Films;
            }

            return matching.ConvertAll(f => MapItem(f, _mediaType));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(
        string externalId,
        string title,
        CancellationToken ct
    )
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
            return null;

        var client = httpClientFactory.CreateClient(Id);
        var endpoint = $"v2.2/films/{Uri.EscapeDataString(externalId)}";

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, endpoint);
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
                return null;

            var item = await resp.Content.ReadFromJsonAsync<KinopoiskDetailItem>(ct);
            if (item is null)
                return null;

            // Seasons live behind a second endpoint and carry the episode air dates, so the show's
            // runtime and its real start/end dates only exist once that call is made. A movie has
            // no seasons, so this is skipped for it.
            var seasons = _mediaType == "tvshow" ? await FetchSeasonsAsync(client, key, externalId, ct) : [];

            return MapDetailItem(item, _mediaType, seasons);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    /// <summary>
    /// Flattens <c>/v2.2/films/{id}/seasons</c> into one ordered episode list. The source returns a
    /// nested season → episode tree, but the app models a single flat list, so episodes are
    /// renumbered sequentially across seasons the way the season UI counts them.
    /// </summary>
    private async Task<List<ExternalEpisodeDto>> FetchSeasonsAsync(
        HttpClient client,
        string key,
        string externalId,
        CancellationToken ct
    )
    {
        try
        {
            using var req = new HttpRequestMessage(
                HttpMethod.Get,
                $"v2.2/films/{Uri.EscapeDataString(externalId)}/seasons"
            );
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
                return [];

            var body = await resp.Content.ReadFromJsonAsync<KinopoiskSeasonsResponse>(ct);
            if (body?.Items is not { Count: > 0 })
                return [];

            var episodes = new List<ExternalEpisodeDto>();
            foreach (
                var season in body.Items
                    .OrderBy(season => season.Number)
                    .SelectMany(season => season.Episodes ?? [])
                    .Where(episode => episode.EpisodeNumber is > 0)
                    .OrderBy(episode => episode.EpisodeNumber)
            )
            {
                episodes.Add(
                    new ExternalEpisodeDto
                    {
                        Number = episodes.Count + 1,
                        Title = !string.IsNullOrWhiteSpace(season.NameRu)
                            ? season.NameRu
                            : season.NameEn ?? string.Empty,
                        AirDate = season.ReleaseDate,
                    }
                );
            }

            return episodes;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            // Seasons are an enrichment; the film itself is still usable without them.
            return [];
        }
    }

    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken ct)
    {
        var key = ApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            return new ConnectionTestResult(false, 0, "API key (X-API-KEY) is required");
        }

        var sw = Stopwatch.StartNew();
        try
        {
            var client = httpClientFactory.CreateClient(Id);
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            using var req = new HttpRequestMessage(
                HttpMethod.Get,
                "v2.1/films/search-by-keyword?keyword=test&page=1"
            );
            req.Headers.Add("X-API-KEY", key);

            using var resp = await client.SendAsync(req, cts.Token);
            sw.Stop();
            if (resp.IsSuccessStatusCode)
            {
                return new ConnectionTestResult(true, (int)sw.ElapsedMilliseconds, "OK");
            }

            return new ConnectionTestResult(
                false,
                (int)sw.ElapsedMilliseconds,
                $"HTTP {(int)resp.StatusCode} {resp.ReasonPhrase}"
            );
        }
        catch (Exception ex)
        {
            sw.Stop();
            return new ConnectionTestResult(false, (int)sw.ElapsedMilliseconds, ex.Message);
        }
    }

    /// <summary>
    /// Compares a Kinopoisk item type against the group being searched. An absent type is kept: the
    /// source did not classify it, so dropping it would hide a legitimate match.
    /// </summary>
    /// <remarks>
    /// The source labels titles FILM / VIDEO / TV_SERIES / MINI_SERIES / TV_SHOW (underscored
    /// enums, upper case), not the "movie" / "tv-series" words this method used to compare against.
    /// Every comparison therefore failed, the strict filter always came back empty, and the
    /// "never return nothing" escape hatch put series into the Movies group and films into the
    /// TV Shows group.
    /// </remarks>
    internal static bool MatchesType(string? itemType, string expectedType)
    {
        if (string.IsNullOrWhiteSpace(itemType))
        {
            return true;
        }

        var normalized = itemType.Trim().ToLowerInvariant().Replace('_', '-');

        return expectedType == "movie"
            ? normalized is "film" or "movie" or "video"
            : normalized
                is "tv-series"
                or "tv-show"
                or "tvshow"
                or "mini-series"
                or "series"
                or "anime"
                or "cartoon"
                or "animated-series";
    }

    /// <summary>
    /// Translates the source's production status into the vocabulary the UI already knows how to
    /// translate. UNKNOWN is dropped so the caller falls back to deriving it from the dates.
    /// </summary>
    internal static string? MapReleaseStatus(string? productionStatus) =>
        productionStatus?.Trim().ToUpperInvariant() switch
        {
            "COMPLETED" => "FINISHED",
            "FILMING" or "POST_PRODUCTION" or "PRE_PRODUCTION" => "RELEASING",
            "ANNOUNCED" => "NOT_YET_RELEASED",
            _ => null,
        };

    /// <summary>
    /// A still-airing show also has an episodes list, so its last air date is only the newest episode.
    /// Reporting it as the end of the run would claim the series finished and fill in a
    /// "Дата окончания" for a show that is still running.
    /// </summary>
    internal static string? ResolveEndDate(
        bool? completed,
        string? productionStatus,
        string? lastAirDate
    ) => completed is true || MapReleaseStatus(productionStatus) == "FINISHED" ? lastAirDate : null;

    /// <summary>
    /// The source has no <c>startDate</c>/<c>endDate</c> on the film itself — only years — but every
    /// season episode carries a full air date, so the first and last episode date are the real
    /// bounds of the show. A movie has no episodes at all, so its dates stay year-only and the
    /// aggregator asks the other sources instead.
    /// </summary>
    internal static (string? Start, string? End) ResolveAirDateRange(
        IReadOnlyList<ExternalEpisodeDto> episodes
    )
    {
        var dates = episodes
            .Select(episode => episode.AirDate)
            .OfType<string>()
            .Select(date => (Date: DateTime.TryParse(date, out var parsed) ? parsed : (DateTime?)null, Raw: date))
            .Where(entry => entry.Date is not null)
            .ToList();

        if (dates.Count == 0)
        {
            return (null, null);
        }

        var earliest = dates.MinBy(entry => entry.Date!.Value)!;
        var latest = dates.MaxBy(entry => entry.Date!.Value)!;

        return (earliest.Raw, latest.Raw);
    }

    private static ExternalMediaDto MapItem(KinopoiskFilmItem item, string type)
    {
        double? score = null;
        if (
            !string.IsNullOrWhiteSpace(item.Rating)
            && double.TryParse(
                item.Rating.TrimEnd('%'),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var parsed
            )
            && parsed > 0
        )
        {
            score = parsed;
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(
                new ExternalRatingDto
                {
                    Source = "Kinopoisk",
                    Rating = Math.Round(score.Value, 1),
                    Votes = item.RatingVoteCount,
                }
            );
        }

        int? year = null;
        if (!string.IsNullOrWhiteSpace(item.Year) && int.TryParse(item.Year, out var y))
        {
            year = y;
        }

        return new ExternalMediaDto
        {
            ExternalId = item.FilmId.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Kinopoisk",
            Title = !string.IsNullOrWhiteSpace(item.NameRu)
                ? item.NameRu
                : (item.NameEn ?? "Unknown"),
            OriginalTitle = item.NameEn,
            CoverUrl = item.PosterUrlPreview ?? item.PosterUrl,
            Description = item.Description,
            ReleaseYear = year,
            // Search results already carry a runtime, so the preview card does not need a second
            // details call just to show it. A movie shows "N мин", a series "N мин/серия".
            RuntimeMinutes = int.TryParse(item.FilmLength, out var length) ? length : null,
            Type = type,
            Rating = score,
            RatingVotes = item.RatingVoteCount,
            Ratings = ratings,
            Genres = item.Genres is { Count: > 0 } searchGenres
                ? [.. searchGenres.Select(genre => genre.Genre).OfType<string>()]
                : null,
        };
    }

    private static ExternalMediaDto MapDetailItem(
        KinopoiskDetailItem item,
        string type,
        IReadOnlyList<ExternalEpisodeDto> episodes
    )
    {
        double? score = item.RatingKinopoisk ?? item.RatingImdb;
        var ratings = new List<ExternalRatingDto>();

        if (score.HasValue && score.Value > 0)
        {
            ratings.Add(
                new ExternalRatingDto
                {
                    Source = "Kinopoisk",
                    Rating = Math.Round(score.Value, 1),
                    Votes = item.RatingKinopoiskVoteCount,
                }
            );
        }

        // Episodes are the only source of a real start/end date here; without them the years below
        // stay year-only so the aggregator knows to ask someone else for the full date.
        var (startDate, endDate) = episodes.Count > 0 ? ResolveAirDateRange(episodes) : (null, null);

        // `completed` is the source's own "no more episodes are coming" flag. A still-airing show has
        // an episodes list too, so its last air date is just the latest episode, NOT the end of the
        // run — reporting it as such would claim the series finished on its most recent air date and
        // make the "Дата окончания" row show a date for a show that is still running.
        var isFinished = item.Completed is true || MapReleaseStatus(item.ProductionStatus) == "FINISHED";
        endDate = ResolveEndDate(item.Completed, item.ProductionStatus, endDate);

        var releaseStatus = isFinished ? "FINISHED" : MapReleaseStatus(item.ProductionStatus);

        return new ExternalMediaDto
        {
            ExternalId = item.KinopoiskId.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Kinopoisk",
            Title = !string.IsNullOrWhiteSpace(item.NameRu)
                ? item.NameRu
                : (item.NameOriginal ?? item.NameEn ?? "Unknown"),
            OriginalTitle = item.NameOriginal ?? item.NameEn,
            CoverUrl = item.PosterUrlPreview ?? item.PosterUrl,
            Description = item.Description,
            // startYear is the premier year and is set for series where `year` may lag behind.
            ReleaseYear = item.StartYear ?? item.Year,
            ReleaseDate = startDate,
            EndDate = endDate,
            ReleaseStatus = releaseStatus,
            // For a series `filmLength` is the average episode runtime, which is what the app
            // stores in EpisodeDurationMinutes; for a film it is the runtime itself.
            RuntimeMinutes = item.FilmLength,
            Type = type,
            Rating = score,
            RatingVotes = item.RatingKinopoiskVoteCount,
            Ratings = ratings,
            Episodes = episodes.Count > 0 ? episodes : null,
            TotalCount = type == "tvshow" ? episodes.Count : null,
            Genres = item.Genres is { Count: > 0 } genres
                ? [.. genres.Select(genre => genre.Genre).OfType<string>()]
                : null,
        };
    }

    private sealed class KinopoiskSearchResponse
    {
        [JsonPropertyName("films")]
        public List<KinopoiskFilmItem>? Films { get; set; }
    }

    private sealed class KinopoiskFilmItem
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

    private sealed class KinopoiskDetailItem
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

    private sealed class KinopoiskGenre
    {
        [JsonPropertyName("genre")]
        public string? Genre { get; set; }
    }

    private sealed class KinopoiskSeasonsResponse
    {
        [JsonPropertyName("total")]
        public int? Total { get; set; }

        [JsonPropertyName("items")]
        public List<KinopoiskSeason>? Items { get; set; }
    }

    private sealed class KinopoiskSeason
    {
        [JsonPropertyName("number")]
        public int Number { get; set; }

        [JsonPropertyName("episodes")]
        public List<KinopoiskEpisode>? Episodes { get; set; }
    }

    private sealed class KinopoiskEpisode
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
}
