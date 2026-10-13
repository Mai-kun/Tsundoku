using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.Import.Parsers;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Features.Media.Import;

public sealed class ImportMediaHandler(
    AppDbContext db,
    IHttpClientFactory clients,
    IConfiguration configuration,
    IOptions<ExternalApiOptions> apiOptions)
{
    public async Task<ImportResultDto> ImportFileAsync(ImportFileRequest request, CancellationToken ct)
    {
        if (request.File.Length == 0) throw new FormatException("The uploaded file is empty.");
        if (request.File.Length > 25 * 1024 * 1024) throw new FormatException("The file must be smaller than 25 MB.");
        using var reader = new StreamReader(request.File.OpenReadStream());
        var content = await reader.ReadToEndAsync(ct);
        var provider = request.Provider.Trim().ToLowerInvariant();
        IReadOnlyList<ParsedMediaItemDto> items;
        try
        {
            items = provider switch
            {
                "mal" => content.TrimStart().StartsWith('<')
                    ? MalXmlParser.Parse(content, request.File.FileName.Contains("manga", StringComparison.OrdinalIgnoreCase))
                        : MalJsonParser.Parse(content, request.File.FileName.Contains("manga", StringComparison.OrdinalIgnoreCase)),
                "shikimori" => content.TrimStart().StartsWith('<')
                    ? MalXmlParser.Parse(content, request.File.FileName.Contains("manga", StringComparison.OrdinalIgnoreCase))
                        .Select(item => item with { ExternalSource = "shikimori" }).ToArray()
                    : ShikimoriImportParser.Parse(content),
                "letterboxd" => LetterboxdCsvParser.Parse(content),
                "goodreads" => GoodreadsCsvParser.Parse(content),
                "steam" => SteamLibraryParser.Parse(content),
                "anilist" => AniListImportParser.Parse(content, request.File.FileName.Contains("manga", StringComparison.OrdinalIgnoreCase)),
                "mangalib" => MangalibParser.Parse(content),
                "custom" => CustomImportParser.Parse(content),
                _ => throw new FormatException("Unsupported import provider.")
            };
        }
        catch (XmlException error) { throw new FormatException("The XML file is malformed.", error); }
        catch (JsonException error) { throw new FormatException("The JSON file is malformed.", error); }
        return await ImportAsync(items, request.SkipDuplicates, request.TargetListId, request.NewListName, ct);
    }

    public async Task<ImportResultDto> ImportSteamAsync(SteamImportRequest request, CancellationToken ct)
    {
        var steamId = request.SteamId?.Trim();
        if (string.IsNullOrWhiteSpace(steamId) && !string.IsNullOrWhiteSpace(request.ProfileUrl))
        {
            var uri = Uri.TryCreate(request.ProfileUrl, UriKind.Absolute, out var parsed) ? parsed : null;
            if (uri is null || !uri.Host.EndsWith("steamcommunity.com", StringComparison.OrdinalIgnoreCase))
                throw new FormatException("Enter a valid Steam profile URL or SteamID64.");
            var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (segments.Length >= 2 && segments[0].Equals("profiles", StringComparison.OrdinalIgnoreCase)) steamId = segments[1];
            else if (segments.Length >= 2 && segments[0].Equals("id", StringComparison.OrdinalIgnoreCase))
            {
                var response = await clients.CreateClient("steam").GetAsync($"https://steamcommunity.com/id/{Uri.EscapeDataString(segments[1])}/?xml=1", ct);
                response.EnsureSuccessStatusCode();
                var xml = await response.Content.ReadAsStringAsync(ct);
                var match = Regex.Match(xml, "<steamID64>(\\d+)</steamID64>");
                steamId = match.Success ? match.Groups[1].Value : null;
            }
        }
        if (string.IsNullOrWhiteSpace(steamId) || steamId.Length != 17 || !steamId.All(char.IsDigit)) throw new FormatException("Could not resolve this profile to a SteamID64.");
        var api = clients.CreateClient("steam");
        var key = !string.IsNullOrWhiteSpace(request.SteamApiKey)
            ? request.SteamApiKey
            : apiOptions.Value.GetKey("steam");
        key = string.IsNullOrWhiteSpace(key) ? configuration["Steam:ApiKey"] : key;
        var keyParameter = string.IsNullOrWhiteSpace(key) ? "" : $"&key={Uri.EscapeDataString(key)}";
        var result = await api.GetAsync($"https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?steamid={Uri.EscapeDataString(steamId)}&include_appinfo=true&include_played_free_games=true{keyParameter}", ct);
        result.EnsureSuccessStatusCode();
        var json = await result.Content.ReadAsStringAsync(ct);
        var games = SteamLibraryParser.Parse(json);
        if (games.Count == 0) throw new FormatException("Steam returned no games. Check that the profile and game details are public.");
        return await ImportAsync(games, request.SkipDuplicates, request.TargetListId, request.NewListName, ct);
    }

    /// <summary>
    /// AniList's public GraphQL endpoint answers MediaListCollection without an API key, so the
    /// username flow reuses the file parser: one ANIME and one MANGA query, entries flattened into
    /// the same ParsedMediaItemDto pipeline.
    /// </summary>
    public async Task<ImportResultDto> ImportAniListProfileAsync(AniListProfileRequest request, CancellationToken ct)
    {
        var username = request.Username?.Trim();
        if (string.IsNullOrWhiteSpace(username)) throw new FormatException("Enter an AniList username.");
        var client = clients.CreateClient();
        var items = new List<ParsedMediaItemDto>();
        foreach (var type in new[] { "ANIME", "MANGA" })
        {
            var payload = JsonSerializer.Serialize(new
            {
                query = "query ($userName: String, $type: MediaType) { MediaListCollection(userName: $userName, type: $type) { lists { entries { progress status score media { id type format title { romaji english native } description(asHtml: false) coverImage { extraLarge large } startDate { year month day } endDate { year month day } status averageScore genres chapters volumes episodes duration countryOfOrigin studios(isMain: true) { nodes { name } } staff(perPage: 3) { edges { role node { name { full } } } } } } } } }",
                variables = new { userName = username, type }
            });
            using var content = new StringContent(payload, global::System.Text.Encoding.UTF8, "application/json");
            using var response = await client.PostAsync("https://graphql.anilist.co", content, ct);
            var json = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode) throw new FormatException(AniListError(json) ?? $"AniList request failed ({(int)response.StatusCode}).");
            try { items.AddRange(AniListImportParser.Parse(json, mangaFile: type == "MANGA")); }
            catch (JsonException error) { throw new FormatException("AniList returned a malformed response.", error); }
        }
        if (items.Count == 0) throw new FormatException($"AniList has no public lists for '{username}'.");
        return await ImportAsync(items, request.SkipDuplicates, request.TargetListId, request.NewListName, ct);
    }

    private static string? AniListError(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() > 0
                && errors[0].TryGetProperty("message", out var message)) return message.ToString();
        }
        catch (JsonException) { /* non-JSON error body: fall back to the status code */ }
        return null;
    }

    private async Task<ImportResultDto> ImportAsync(IReadOnlyList<ParsedMediaItemDto> parsed, bool skipDuplicates, Guid? targetListId, string? newListName, CancellationToken ct)
    {
        CustomList? list = null;
        if (!string.IsNullOrWhiteSpace(newListName))
        {
            list = new CustomList { Name = newListName.Trim(), UpdatedAt = DateTime.UtcNow };
            db.CustomLists.Add(list);
        }
        else if (targetListId is { } id)
        {
            list = await db.CustomLists.SingleOrDefaultAsync(value => value.Id == id, ct)
                ?? throw new FormatException("The selected list does not exist.");
        }

        var existing = await db.MediaItems.ToListAsync(ct);
        await db.TvShows.Include(s => s.Seasons).LoadAsync(ct);

        var byExternalKey = existing
            .Where(item => !string.IsNullOrWhiteSpace(item.ExternalId))
            .GroupBy(item => $"{item.ExternalSource}\u001f{item.ExternalId}", StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var byTitleKey = new Dictionary<string, MediaItem>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in existing)
        {
            var type = GetType(item);
            byTitleKey.TryAdd($"{type}\u001f{item.Title.Trim()}", item);
            string? romaji = item switch
            {
                Manga m => m.RomajiTitle,
                Movie mov => mov.RomajiTitle,
                TvShow tv => tv.RomajiTitle,
                _ => null
            };
            if (!string.IsNullOrWhiteSpace(romaji))
            {
                byTitleKey.TryAdd($"{type}\u001f{romaji.Trim()}", item);
            }
        }

        var toAdd = new List<MediaItem>();
        var duplicateCount = 0;
        foreach (var dto in parsed)
        {
            var externalKey = string.IsNullOrWhiteSpace(dto.ExternalId) ? null : $"{dto.ExternalSource}\u001f{dto.ExternalId}";
            var titleKey = $"{dto.Type}\u001f{dto.Title.Trim()}";

            MediaItem? match = null;
            if (externalKey is not null && byExternalKey.TryGetValue(externalKey, out match))
            {
            }
            else if (byTitleKey.TryGetValue(titleKey, out match))
            {
            }
            else if (!string.IsNullOrWhiteSpace(dto.RomajiTitle) && byTitleKey.TryGetValue($"{dto.Type}\u001f{dto.RomajiTitle.Trim()}", out match))
            {
            }

            if (match is not null)
            {
                HealExisting(match, dto);
                if (skipDuplicates)
                {
                    duplicateCount++;
                    continue;
                }
            }

            var item = CreateItem(dto);
            toAdd.Add(item);
            if (externalKey is not null) byExternalKey.TryAdd(externalKey, item);
            byTitleKey.TryAdd(titleKey, item);
        }

        db.MediaItems.AddRange(toAdd);
        if (list is not null)
        {
            var order = await db.CustomListItems.Where(item => item.ListId == list.Id).Select(item => (int?)item.Order).MaxAsync(ct) ?? -1;
            foreach (var item in toAdd) db.CustomListItems.Add(new CustomListItem { ListId = list.Id, List = list, MediaItem = item, Order = ++order });
            list.UpdatedAt = DateTime.UtcNow;
        }
        await db.SaveChangesAsync(ct);
        return new ImportResultDto(parsed.Count, toAdd.Count, duplicateCount, list?.Id, list?.Name);
    }

    private static void HealExisting(MediaItem existing, ParsedMediaItemDto parsed)
    {
        var modified = false;

        if (string.IsNullOrEmpty(existing.CoverUrl) && !string.IsNullOrWhiteSpace(parsed.CoverUrl))
        {
            existing.CoverUrl = parsed.CoverUrl;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(existing.Description) && !string.IsNullOrWhiteSpace(parsed.Description))
        {
            existing.Description = parsed.Description;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(existing.Genres) && !string.IsNullOrWhiteSpace(parsed.Genres))
        {
            existing.Genres = parsed.Genres;
            modified = true;
        }

        var releaseDate = ParseDate(parsed.ReleaseDate);
        if (existing.ReleaseDate is null && releaseDate is not null)
        {
            existing.SetReleaseDate(releaseDate, parsed.ReleaseYear ?? existing.ReleaseYear);
            modified = true;
        }
        else if (existing.ReleaseYear is null or <= 0 && parsed.ReleaseYear is > 0)
        {
            existing.SetReleaseDate(existing.ReleaseDate, parsed.ReleaseYear);
            modified = true;
        }

        var endDate = ParseDate(parsed.EndDate);
        if (existing.EndDate is null && endDate is not null)
        {
            existing.EndDate = endDate;
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(existing.ReleaseStatus) && !string.IsNullOrWhiteSpace(parsed.ReleaseStatus))
        {
            existing.ReleaseStatus = parsed.ReleaseStatus;
            modified = true;
        }

        if (existing.ExternalRating is null && parsed.Rating is > 0)
        {
            existing.ExternalRating = parsed.Rating;
            existing.ExternalRatingVotes = parsed.RatingVotes ?? existing.ExternalRatingVotes;
            if (string.IsNullOrWhiteSpace(existing.ExternalRatingsJson))
            {
                existing.ExternalRatingsJson = SerializeExternalRating(parsed.ExternalSource, parsed.Rating.Value, parsed.RatingVotes);
            }
            modified = true;
        }

        if (string.IsNullOrWhiteSpace(existing.ExternalId) && !string.IsNullOrWhiteSpace(parsed.ExternalId))
        {
            existing.ExternalId = parsed.ExternalId;
            existing.ExternalSource ??= parsed.ExternalSource;
            modified = true;
        }

        switch (existing)
        {
            case Book book:
                if (string.IsNullOrWhiteSpace(book.Author) && !string.IsNullOrWhiteSpace(parsed.Author))
                {
                    book.Author = parsed.Author;
                    modified = true;
                }
                if (book.TotalPages <= 0 && parsed.TotalCount is > 0)
                {
                    book.TotalPages = parsed.TotalCount.Value;
                    modified = true;
                }
                break;

            case Manga manga:
                if (string.IsNullOrWhiteSpace(manga.Author) && !string.IsNullOrWhiteSpace(parsed.Author))
                {
                    manga.Author = parsed.Author;
                    modified = true;
                }
                if (string.IsNullOrWhiteSpace(manga.RomajiTitle) && !string.IsNullOrWhiteSpace(parsed.RomajiTitle))
                {
                    manga.RomajiTitle = parsed.RomajiTitle;
                    modified = true;
                }
                if (manga.TotalChapters is not > 0 && parsed.TotalCount is > 0)
                {
                    manga.RecordTotalChapters(parsed.TotalCount.Value);
                    modified = true;
                }
                if (manga.TotalVolumes is not > 0 && parsed.TotalVolumes is > 0)
                {
                    manga.RecordTotalVolumes(parsed.TotalVolumes.Value);
                    modified = true;
                }
                break;

            case Movie movie:
                if (string.IsNullOrWhiteSpace(movie.Studio) && !string.IsNullOrWhiteSpace(parsed.Studio))
                {
                    movie.Studio = parsed.Studio;
                    modified = true;
                }
                if (string.IsNullOrWhiteSpace(movie.Director) && !string.IsNullOrWhiteSpace(parsed.Director))
                {
                    movie.Director = parsed.Director;
                    modified = true;
                }
                if (string.IsNullOrWhiteSpace(movie.RomajiTitle) && !string.IsNullOrWhiteSpace(parsed.RomajiTitle))
                {
                    movie.RomajiTitle = parsed.RomajiTitle;
                    modified = true;
                }
                if (movie.DurationMinutes <= 0 && parsed.DurationMinutes is > 0)
                {
                    movie.DurationMinutes = parsed.DurationMinutes.Value;
                    modified = true;
                }
                break;

            case TvShow show:
                if (string.IsNullOrWhiteSpace(show.Studio) && !string.IsNullOrWhiteSpace(parsed.Studio))
                {
                    show.Studio = parsed.Studio;
                    show.Network ??= parsed.Studio;
                    modified = true;
                }
                if (string.IsNullOrWhiteSpace(show.RomajiTitle) && !string.IsNullOrWhiteSpace(parsed.RomajiTitle))
                {
                    show.RomajiTitle = parsed.RomajiTitle;
                    modified = true;
                }
                if (show.Seasons.Count > 0 && parsed.TotalCount is > 0)
                {
                    var season = show.Seasons[0];
                    if (season.TotalEpisodes <= 0)
                    {
                        season.TotalEpisodes = parsed.TotalCount.Value;
                        modified = true;
                    }
                }
                break;

            case VideoGame game:
                if ((string.IsNullOrWhiteSpace(game.Platform) || game.Platform == "Steam") && !string.IsNullOrWhiteSpace(parsed.Platform))
                {
                    game.Platform = parsed.Platform;
                    modified = true;
                }
                if (string.IsNullOrWhiteSpace(game.Studio) && !string.IsNullOrWhiteSpace(parsed.Studio))
                {
                    game.Studio = parsed.Studio;
                    modified = true;
                }
                break;
        }

        if (modified)
        {
            existing.MarkUpdated();
        }
    }

    private static MediaItem CreateItem(ParsedMediaItemDto dto)
    {
        MediaItem item = dto.Type switch
        {
            "book" => new Book { Title = dto.Title, Author = dto.Author ?? "", TotalPages = Math.Max(0, dto.TotalCount ?? 0), CurrentPage = dto.Status == MediaStatus.Completed ? Math.Max(0, dto.TotalCount ?? 0) : 0 },
            "manga" => new Manga { Title = dto.Title, Author = dto.Author, RomajiTitle = dto.RomajiTitle, TotalChapters = dto.TotalCount is > 0 ? dto.TotalCount : null, CurrentChapter = Math.Max(0, dto.CurrentProgress ?? 0), CurrentVolume = Math.Max(0, dto.CurrentVolumes ?? 0), TotalVolumes = dto.TotalVolumes is > 0 ? dto.TotalVolumes : null },
            "game" => new VideoGame { Title = dto.Title, Platform = dto.Platform ?? "PC", Studio = dto.Studio, HoursPlayed = Math.Max(0, dto.CurrentProgress ?? 0) },
            "anime" => CreateAnime(dto),
            "movie" => new Movie { Title = dto.Title, Studio = dto.Studio, Director = dto.Director, RomajiTitle = dto.RomajiTitle, DurationMinutes = dto.DurationMinutes ?? 0 },
            "tvshow" => new TvShow { Title = dto.Title, Studio = dto.Studio, RomajiTitle = dto.RomajiTitle, EpisodeDurationMinutes = dto.DurationMinutes is > 0 ? dto.DurationMinutes : null },
            _ => throw new FormatException($"Unsupported media type: {dto.Type}")
        };
        item.SetStatus(dto.Status);
        item.Score = dto.Score is >= 1 and <= 10 ? dto.Score : null;
        item.CoverUrl = dto.CoverUrl;
        item.Description = dto.Description;
        item.Genres = dto.Genres;
        var parsedReleaseDate = ParseDate(dto.ReleaseDate);
        item.SetReleaseDate(parsedReleaseDate, dto.ReleaseYear ?? ParseYear(dto.ReleaseDate));
        item.EndDate = ParseDate(dto.EndDate);
        item.ReleaseStatus = !string.IsNullOrWhiteSpace(dto.ReleaseStatus)
            ? dto.ReleaseStatus
            : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate);
        item.ExternalId = dto.ExternalId;
        item.ExternalSource = dto.ExternalSource;
        item.ExternalRating = dto.Rating;
        item.ExternalRatingVotes = dto.RatingVotes;
        if (dto.Rating is > 0)
        {
            item.ExternalRatingsJson = SerializeExternalRating(dto.ExternalSource, dto.Rating.Value, dto.RatingVotes);
        }
        item.SyncStatus = SyncStatus.Ready;
        if (dto.WatchedAt is { } watched) { item.StartedAt = watched; item.FinishedAt = watched; }
        if (item is Manga manga && dto.Status == MediaStatus.Completed && manga.TotalChapters is > 0) manga.CurrentChapter = manga.TotalChapters.Value;
        return item;
    }

    private static TvShow CreateAnime(ParsedMediaItemDto dto)
    {
        var show = new TvShow
        {
            Title = dto.Title,
            IsAnime = true,
            Studio = dto.Studio,
            RomajiTitle = dto.RomajiTitle,
            EpisodeDurationMinutes = dto.DurationMinutes is > 0 ? dto.DurationMinutes : null
        };
        var season = TvSeason.CreateFirst(Math.Max(0, dto.TotalCount ?? 0), null, dto.Status, show.Id);
        season.SetEpisode(Math.Max(0, dto.CurrentProgress ?? 0));
        if (dto.Status == MediaStatus.Completed) season.MarkCompleted();
        else season.ApplyProgress(dto.Status, Math.Max(0, dto.CurrentProgress ?? 0));
        season.Score = dto.Score;
        show.Seasons.Add(season);
        return show;
    }

    private static string SerializeExternalRating(string? source, double score, int? votes = null)
    {
        var src = string.IsNullOrWhiteSpace(source) ? "Unknown" : source;
        return votes.HasValue
            ? JsonSerializer.Serialize(new[] { new { source = src, score, votes = votes.Value } }, MediaRatingSerializer.JsonOptions)
            : JsonSerializer.Serialize(new[] { new { source = src, score } }, MediaRatingSerializer.JsonOptions);
    }

    private static DateTime? ParseDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) && value.Trim().Length >= 8
            ? date
            : null;
    }

    private static int? ParseYear(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) && value.Trim().Length >= 8)
            return date.Year;
        return int.TryParse(value.Trim().Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
    }

    private static string GetType(MediaItem item) => item switch
    {
        Book => "book", Manga => "manga", VideoGame => "game",
        Movie movie when movie.IsAnime => "anime", TvShow show when show.IsAnime => "anime",
        Movie => "movie", TvShow => "tvshow", _ => ""
    };
}
