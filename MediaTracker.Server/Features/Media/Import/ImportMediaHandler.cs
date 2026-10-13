using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
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
                    : ParseShikimori(content),
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
                query = "query ($userName: String, $type: MediaType) { MediaListCollection(userName: $userName, type: $type) { lists { entries { progress status score media { id type episodes chapters title { english romaji native } } } } } }",
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

        var existing = await db.MediaItems.AsNoTracking().ToListAsync(ct);
        var externalKeys = existing.Where(item => !string.IsNullOrWhiteSpace(item.ExternalId))
            .Select(item => $"{item.ExternalSource}\u001f{item.ExternalId}").ToHashSet(StringComparer.OrdinalIgnoreCase);
        var titleKeys = existing.Select(item => $"{GetType(item)}\u001f{item.Title.Trim()}").ToHashSet(StringComparer.OrdinalIgnoreCase);
        var toAdd = new List<MediaItem>();
        var duplicateCount = 0;
        foreach (var dto in parsed)
        {
            var externalKey = string.IsNullOrWhiteSpace(dto.ExternalId) ? null : $"{dto.ExternalSource}\u001f{dto.ExternalId}";
            var titleKey = $"{dto.Type}\u001f{dto.Title.Trim()}";
            if (skipDuplicates && ((externalKey is not null && externalKeys.Contains(externalKey)) || titleKeys.Contains(titleKey)))
            { duplicateCount++; continue; }
            var item = CreateItem(dto);
            toAdd.Add(item);
            if (externalKey is not null) externalKeys.Add(externalKey);
            titleKeys.Add(titleKey);
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

    private static MediaItem CreateItem(ParsedMediaItemDto dto)
    {
        MediaItem item = dto.Type switch
        {
            "book" => new Book { Title = dto.Title, Author = dto.Author ?? "", TotalPages = Math.Max(0, dto.TotalCount ?? 0), CurrentPage = dto.Status == MediaStatus.Completed ? Math.Max(0, dto.TotalCount ?? 0) : 0 },
            "manga" => new Manga { Title = dto.Title, Author = dto.Author, TotalChapters = dto.TotalCount is > 0 ? dto.TotalCount : null, CurrentChapter = Math.Max(0, dto.CurrentProgress ?? 0), CurrentVolume = Math.Max(0, dto.CurrentVolumes ?? 0), TotalVolumes = dto.TotalVolumes is > 0 ? dto.TotalVolumes : null },
            "game" => new VideoGame { Title = dto.Title, Platform = "Steam", HoursPlayed = Math.Max(0, dto.CurrentProgress ?? 0) },
            "anime" => CreateAnime(dto),
            "movie" => new Movie { Title = dto.Title },
            "tvshow" => new TvShow { Title = dto.Title },
            _ => throw new FormatException($"Unsupported media type: {dto.Type}")
        };
        item.SetStatus(dto.Status);
        item.Score = dto.Score is >= 1 and <= 10 ? dto.Score : null;
        item.SetReleaseDate(null, dto.ReleaseYear);
        item.ExternalId = dto.ExternalId;
        item.ExternalSource = dto.ExternalSource;
        item.SyncStatus = SyncStatus.Ready;
        if (dto.WatchedAt is { } watched) { item.StartedAt = watched; item.FinishedAt = watched; }
        if (item is Manga manga && dto.Status == MediaStatus.Completed && manga.TotalChapters is > 0) manga.CurrentChapter = manga.TotalChapters.Value;
        return item;
    }

    private static TvShow CreateAnime(ParsedMediaItemDto dto)
    {
        var show = new TvShow { Title = dto.Title, IsAnime = true };
        var season = TvSeason.CreateFirst(Math.Max(0, dto.TotalCount ?? 0), null, dto.Status, show.Id);
        season.SetEpisode(Math.Max(0, dto.CurrentProgress ?? 0));
        if (dto.Status == MediaStatus.Completed) season.MarkCompleted();
        else season.ApplyProgress(dto.Status, Math.Max(0, dto.CurrentProgress ?? 0));
        season.Score = dto.Score;
        show.Seasons.Add(season);
        return show;
    }

    private static string GetType(MediaItem item) => item switch
    {
        Book => "book", Manga => "manga", VideoGame => "game",
        Movie movie when movie.IsAnime => "anime", TvShow show when show.IsAnime => "anime",
        Movie => "movie", TvShow => "tvshow", _ => ""
    };

    private static IReadOnlyList<ParsedMediaItemDto> ParseShikimori(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data)) root = data;
        if (root.ValueKind != JsonValueKind.Array) throw new FormatException("Shikimori JSON must contain an array of list entries.");
        return root.EnumerateArray().Select(entry =>
        {
            var anime = entry.TryGetProperty("anime", out var a) ? a : entry.TryGetProperty("manga", out var m) ? m : entry;
            string? Value(JsonElement e, string key) => e.TryGetProperty(key, out var value) ? value.ToString() : null;
            int? Number(JsonElement e, string key) => int.TryParse(Value(e, key), CultureInfo.InvariantCulture, out var n) ? n : null;
            var statusText = (Value(entry, "status") ?? "").ToLowerInvariant();
            var manga = entry.TryGetProperty("manga", out _);
            var status = statusText switch { "watching" or "reading" => MediaStatus.InProgress, "completed" => MediaStatus.Completed, "on_hold" => MediaStatus.OnHold, "dropped" => MediaStatus.Dropped, _ => MediaStatus.Planned };
            return new ParsedMediaItemDto(Value(anime, "name") ?? Value(anime, "russian") ?? "", manga ? "manga" : "anime", status,
                Number(entry, "score") is > 0 and var score ? score : null,
                Number(entry, manga ? "chapters" : "episodes"), Number(anime, manga ? "chapters" : "episodes"),
                ReleaseYear: ParseYear(Value(anime, "aired_on")), ExternalId: Value(anime, "id"), ExternalSource: "shikimori",
                CurrentVolumes: manga ? Number(entry, "volumes") : null,
                TotalVolumes: manga ? Number(anime, "volumes") : null);
        }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();
    }

    private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, out var date)
        ? date.Year
        : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
}
