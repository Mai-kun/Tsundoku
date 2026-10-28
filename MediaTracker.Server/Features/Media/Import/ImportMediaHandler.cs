using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.Import.Parsers;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Features.Media.GetMediaStats;
using Microsoft.Extensions.Options;

using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.Media.Import;

public sealed class ImportMediaHandler(
    AppDbContext db,
    IHttpClientFactory clients,
    IConfiguration configuration,
    IOptions<ExternalApiOptions> apiOptions,
    IJobManager? jobs = null)
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
        return await ImportAsync(
            items,
            request.SkipDuplicates,
            request.TargetListId,
            request.NewListName,
            ct,
            request.CreateCustomLists,
            request.CustomFolderStatus,
            request.CustomFolderConfigs);
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
    public async Task<Result<ImportResultDto>> ImportAniListProfileAsync(AniListProfileRequest request, CancellationToken ct)
    {
        var username = request.Username?.Trim();
        if (string.IsNullOrWhiteSpace(username))
            return Result<ImportResultDto>.Failure(Error.Validation("Enter an AniList username."));

        // Named so the external-call logger (AddHttpMessageHandler on "Import") sees the traffic.
        var client = clients.CreateClient("Import");
        var items = new List<ParsedMediaItemDto>();
        foreach (var type in new[] { "ANIME", "MANGA" })
        {
            var payload = JsonSerializer.Serialize(new AniListProfileGraphQlPayload(
                    "query ($userName: String, $type: MediaType) { MediaListCollection(userName: $userName, type: $type) { lists { entries { progress status score media { id type format title { romaji english native } description coverImage { extraLarge large } startDate { year month day } endDate { year month day } status averageScore genres chapters volumes episodes } } } } }",
                    new AniListProfileVariables(username, type)), AppJsonSerializerContext.Default.AniListProfileGraphQlPayload);
            using var content = new StringContent(payload, global::System.Text.Encoding.UTF8, "application/json");
            using var response = await client.PostAsync("https://graphql.anilist.co", content, ct);
            var json = await response.Content.ReadAsStringAsync(ct);

            if (!response.IsSuccessStatusCode)
            {
                var errMsg = AniListError(json) ?? $"AniList request failed ({(int)response.StatusCode}).";
                return Result<ImportResultDto>.Failure(Error.Validation($"AniList error: {errMsg}"));
            }

            try
            {
                using var document = JsonDocument.Parse(json);
                var root = document.RootElement;
                bool hasErrors = root.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() > 0;
                bool dataIsNull = !root.TryGetProperty("data", out var data) || data.ValueKind == JsonValueKind.Null;

                if (hasErrors && dataIsNull)
                {
                    string msg = "Unknown error";
                    if (errors[0].ValueKind == JsonValueKind.Object &&
                        errors[0].TryGetProperty("message", out var msgProp) &&
                        msgProp.ValueKind == JsonValueKind.String)
                    {
                        msg = msgProp.GetString() ?? "Unknown error";
                    }
                    return Result<ImportResultDto>.Failure(Error.Validation($"AniList error: {msg}"));
                }
            }
            catch (JsonException)
            {
                return Result<ImportResultDto>.Failure(Error.Validation("AniList returned a malformed response."));
            }

            try
            {
                items.AddRange(AniListImportParser.Parse(json, mangaFile: type == "MANGA"));
            }
            catch (FormatException ex)
            {
                return Result<ImportResultDto>.Failure(Error.Validation(ex.Message));
            }
            catch (JsonException)
            {
                return Result<ImportResultDto>.Failure(Error.Validation("AniList returned a malformed response."));
            }
        }

        if (items.Count == 0)
            return Result<ImportResultDto>.Failure(Error.Validation($"AniList has no public lists for '{username}'."));

        var importResult = await ImportAsync(items, request.SkipDuplicates, request.TargetListId, request.NewListName, ct);
        return Result<ImportResultDto>.Success(importResult);
    }

    private static string? AniListError(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.TryGetProperty("errors", out var errors) &&
                errors.ValueKind == JsonValueKind.Array &&
                errors.GetArrayLength() > 0 &&
                errors[0].ValueKind == JsonValueKind.Object &&
                errors[0].TryGetProperty("message", out var message) &&
                message.ValueKind == JsonValueKind.String)
            {
                return message.GetString();
            }
        }
        catch (JsonException) { /* non-JSON error body: fall back to the status code */ }
        return null;
    }

    /// <summary>
    /// Direct SocialLib ecosystem import (MangaLib, AnimeLib, RanobeLib, SlashLib, HentaiLib).
    /// Queries https://api.cdnlibs.org/api/bookmarks for each selected site_id.
    /// </summary>
    public async Task<Result<ImportResultDto>> ImportMangaLibProfileAsync(MangaLibProfileRequest request, CancellationToken ct)
    {
        var rawInput = request.ProfileUrlOrId?.Trim();
        if (string.IsNullOrWhiteSpace(rawInput))
            return Result<ImportResultDto>.Failure(Error.Validation("Укажите ссылку на профиль или числовой ID пользователя SocialLib."));

        var userId = ExtractSocialLibUserId(rawInput);
        if (string.IsNullOrWhiteSpace(userId))
            return Result<ImportResultDto>.Failure(Error.Validation("Не удалось определить ID пользователя из указанной ссылки."));

        var client = clients.CreateClient("Import");
        var siteIds = request.SiteIds is { Length: > 0 } ? request.SiteIds : [1, 5, 3, 2, 4];
        var allItems = new List<ParsedMediaItemDto>();
        var totalSitesQueried = 0;
        var authErrorCount = 0;
        var statuses = new[] { 1, 2, 4, 3, 6, 5 };

        foreach (var siteId in siteIds)
        {
            totalSitesQueried++;
            var siteAuthError = false;
            var siteFolderIds = await FetchSocialLibFolderIdsAsync(client, userId, siteId, request.BearerToken, ct);

            foreach (var statusId in siteFolderIds)
            {
                if (siteAuthError) break;

                var page = 1;
                while (page <= 50)
                {
                    var url = $"https://api.cdnlibs.org/api/bookmarks?user_id={Uri.EscapeDataString(userId)}&site_id={siteId}&status={statusId}&page={page}&limit=60&fields[]=summary&fields[]=genres&fields[]=authors&fields[]=chap_count&fields[]=rate";
                    using var msg = CreateSocialLibMessage(url, siteId, request.BearerToken);

                    HttpResponseMessage? response = null;
                    try
                    {
                        response = await client.SendAsync(msg, ct);
                    }
                    catch (HttpRequestException)
                    {
                        break;
                    }

                    using (response)
                    {
                        if ((int)response.StatusCode is 401 or 403)
                        {
                            authErrorCount++;
                            siteAuthError = true;
                            break;
                        }

                        if (!response.IsSuccessStatusCode)
                            break;

                        var json = await response.Content.ReadAsStringAsync(ct);
                        IReadOnlyList<ParsedMediaItemDto> pageItems;
                        try
                        {
                            pageItems = MangalibParser.Parse(json, defaultSiteId: siteId, defaultStatusId: statusId);
                        }
                        catch
                        {
                            break;
                        }

                        if (pageItems.Count == 0) break;

                        allItems.AddRange(pageItems);
                        if (pageItems.Count < 60) break;
                        page++;
                    }
                }
            }
        }

        if (allItems.Count == 0)
        {
            if (totalSitesQueried > 0 && authErrorCount == totalSitesQueried)
            {
                return Result<ImportResultDto>.Failure(Error.Validation("API SocialLib закрыт защитой Cloudflare или профиль приватный. Воспользуйтесь встроенным быстрым скриптом-сборщиком ниже (работает за 1 секунду прямо из браузера)!"));
            }

            return Result<ImportResultDto>.Failure(Error.Validation($"У пользователя {userId} не найдено закладок на выбранных сайтах SocialLib."));
        }

        var importResult = await ImportAsync(allItems, request.SkipDuplicates, request.TargetListId, request.NewListName, ct);
        return Result<ImportResultDto>.Success(importResult);
    }

    private static string? ExtractSocialLibUserId(string input)
    {
        var trimmed = input.Trim();
        if (trimmed.All(char.IsDigit) && trimmed.Length > 0)
            return trimmed;

        var match = Regex.Match(trimmed, @"/(?:ru/)?user[s]?/(\d+)", RegexOptions.IgnoreCase);
        if (match.Success) return match.Groups[1].Value;

        match = Regex.Match(trimmed, @"\buser[s]?/(\d+)", RegexOptions.IgnoreCase);
        if (match.Success) return match.Groups[1].Value;

        match = Regex.Match(trimmed, @"[?&]user_id=(\d+)", RegexOptions.IgnoreCase);
        if (match.Success) return match.Groups[1].Value;

        match = Regex.Match(trimmed, @"@(\d+)");
        if (match.Success) return match.Groups[1].Value;

        match = Regex.Match(trimmed, @"\b(\d{3,})\b");
        if (match.Success) return match.Groups[1].Value;

        return null;
    }

    private static HttpRequestMessage CreateSocialLibMessage(string url, int siteId, string? bearerToken)
    {
        var msg = new HttpRequestMessage(HttpMethod.Get, url);
        msg.Headers.TryAddWithoutValidation("Site-Id", siteId.ToString(CultureInfo.InvariantCulture));
        msg.Headers.TryAddWithoutValidation("Accept", "application/json");
        msg.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

        if (!string.IsNullOrWhiteSpace(bearerToken))
        {
            var token = bearerToken.Trim();
            if (token.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                token = token["Bearer ".Length..].Trim();
            msg.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
        }

        return msg;
    }

    private static async Task<IReadOnlyList<int>> FetchSocialLibFolderIdsAsync(HttpClient client, string userId, int siteId, string? bearerToken, CancellationToken ct)
    {
        try
        {
            var url = $"https://api.cdnlibs.org/api/bookmarks/folder/{Uri.EscapeDataString(userId)}?site_id={siteId}";
            using var msg = CreateSocialLibMessage(url, siteId, bearerToken);
            using var res = await client.SendAsync(msg, ct);
            if (res.IsSuccessStatusCode)
            {
                var json = await res.Content.ReadAsStringAsync(ct);
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data))
                    root = data;
                if (root.ValueKind == JsonValueKind.Array)
                {
                    var ids = new List<int>();
                    foreach (var elem in root.EnumerateArray())
                    {
                        if (elem.TryGetProperty("id", out var idProp) && idProp.TryGetInt32(out var id))
                            ids.Add(id);
                    }
                    if (ids.Count > 0) return ids;
                }
            }
        }
        catch
        {
        }

        return [1, 2, 4, 3, 6, 5];
    }

    private async Task<ImportResultDto> ImportAsync(
        IReadOnlyList<ParsedMediaItemDto> parsed,
        bool skipDuplicates,
        Guid? targetListId,
        string? newListName,
        CancellationToken ct,
        bool createCustomLists = false,
        MediaStatus? customFolderStatus = null,
        string? customFolderConfigs = null)
    {
        CustomList? list = null;
        if (!string.IsNullOrWhiteSpace(newListName))
        {
            list = new CustomList { Name = newListName.Trim(), UpdatedAt = DateTime.UtcNow };
            await db.CreateCustomListAsync(list, ct);
        }
        else if (targetListId is { } id)
        {
            list = await db.GetCustomListAsync(id, ct)
                ?? throw new FormatException("The selected list does not exist.");
        }

        Dictionary<string, CustomFolderSetting>? folderConfigs = null;
        if (!string.IsNullOrWhiteSpace(customFolderConfigs))
        {
            try
            {
                folderConfigs = JsonSerializer.Deserialize(customFolderConfigs, AppJsonSerializerContext.Default.DictionaryStringCustomFolderSetting);
            }
            catch
            {
            }
        }

        var existing = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);

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
        var healedMatches = new List<MediaItem>();
        var duplicateCount = 0;
        var skippedTitles = new List<string>();
        var customFolderAssignments = new List<(string FolderName, MediaItem Item)>();

        foreach (var originalDto in parsed)
        {
            var dto = originalDto;
            CustomFolderSetting? folderSetting = null;
            if (dto.IsCustomFolder == true && !string.IsNullOrWhiteSpace(dto.FolderName) && folderConfigs != null)
            {
                folderConfigs.TryGetValue(dto.FolderName.Trim(), out folderSetting);
            }

            if (folderSetting is { Skip: true })
            {
                continue;
            }
            if (folderSetting?.Status != null &&
                (folderSetting.Status.Equals("skip", StringComparison.OrdinalIgnoreCase) ||
                 folderSetting.Status.Equals("ignore", StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (folderSetting?.Status != null &&
                Enum.TryParse<MediaStatus>(folderSetting.Status, true, out var customStatus))
            {
                dto = dto with { Status = customStatus };
            }
            else if (customFolderStatus.HasValue && dto.IsCustomFolder == true)
            {
                dto = dto with { Status = customFolderStatus.Value };
            }

            var shouldCreateList = folderSetting != null
                ? folderSetting.CreateList
                : createCustomLists;

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
                healedMatches.Add(match);
                if (folderSetting?.Status != null &&
                    Enum.TryParse<MediaStatus>(folderSetting.Status, true, out var customMatchStatus))
                {
                    match.Status = customMatchStatus;
                }
                else if (customFolderStatus.HasValue && dto.IsCustomFolder == true)
                {
                    match.Status = customFolderStatus.Value;
                }

                if (shouldCreateList && dto.IsCustomFolder == true && !string.IsNullOrWhiteSpace(dto.FolderName))
                {
                    customFolderAssignments.Add((dto.FolderName.Trim(), match));
                }

                if (skipDuplicates)
                {
                    duplicateCount++;
                    skippedTitles.Add(dto.Title);
                    continue;
                }
            }

            var item = CreateItem(dto);
            toAdd.Add(item);
            if (externalKey is not null) byExternalKey.TryAdd(externalKey, item);
            byTitleKey.TryAdd(titleKey, item);

            if (shouldCreateList && dto.IsCustomFolder == true && !string.IsNullOrWhiteSpace(dto.FolderName))
            {
                customFolderAssignments.Add((dto.FolderName.Trim(), item));
            }
        }

        foreach (var item in toAdd) await db.InsertMediaItemAsync(item, ct);
        // HealExisting mutates matched rows in place; without EF change tracking the writes are explicit.
        foreach (var healed in healedMatches.DistinctBy(m => m.Id)) await db.UpdateMediaItemAsync(healed, ct);
        if (list is not null)
        {
            var existingItems = await db.GetCustomListItemsAsync(list.Id, ct);
            var order = existingItems.Count > 0 ? existingItems.Max(i => i.Order) : -1;
            foreach (var item in toAdd)
            {
                await db.AddCustomListItemAsync(list.Id, item.Id, ct);
            }
            list.UpdatedAt = DateTime.UtcNow;
            await db.UpdateCustomListAsync(list, ct);
        }

        if (customFolderAssignments.Count > 0)
        {
            var uniqueFolderNames = customFolderAssignments
                .Select(x => x.FolderName)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            var existingLists = (await db.GetCustomListsAsync(ct))
                .Where(l => uniqueFolderNames.Contains(l.Name))
                .ToList();

            var listMap = existingLists.ToDictionary(l => l.Name, StringComparer.OrdinalIgnoreCase);

            foreach (var folderName in uniqueFolderNames)
            {
                if (!listMap.TryGetValue(folderName, out var customList))
                {
                    customList = new CustomList { Name = folderName, UpdatedAt = DateTime.UtcNow };
                    await db.CreateCustomListAsync(customList, ct);
                    listMap[folderName] = customList;
                }
            }

            foreach (var group in customFolderAssignments.GroupBy(x => x.FolderName, StringComparer.OrdinalIgnoreCase))
            {
                var customList = listMap[group.Key];
                var existingItemIds = new HashSet<Guid>(customList.Items.Select(ci => ci.MediaItemId));
                var maxOrder = customList.Items.Count > 0 ? customList.Items.Max(ci => ci.Order) : -1;

                var distinctItems = group.Select(x => x.Item).DistinctBy(x => x.Id).ToList();
                foreach (var mediaItem in distinctItems)
                {
                    if (existingItemIds.Contains(mediaItem.Id)) continue;

                    await db.AddCustomListItemAsync(customList.Id, mediaItem.Id, ct);
                    existingItemIds.Add(mediaItem.Id);
                }
                customList.UpdatedAt = DateTime.UtcNow;
            }
        }

        // Import parsers study hand-maintained lists, so new rows arrive with names and progress but
        // no poster, synopsis or genres. Mark those and hand the whole batch to one queued job: a
        // single throttled walk through the aggregator instead of N parallel providers calls. The
        // null check is just for the self-check harness, which builds the handler without the queue.
        var itemsToEnrich = jobs is not null ? toAdd.Where(NeedsEnrichment).ToList() : [];
        if (itemsToEnrich.Count > 0)
        {
            foreach (var item in itemsToEnrich)
            {
                item.SyncStatus = SyncStatus.Syncing;
            }
            jobs!.Enqueue(
                null,
                $"Обогащение импорта ({itemsToEnrich.Count} тайтлов)",
                (sp, token, progress) => BatchImportEnrichmentJob.RunAsync(sp, [.. itemsToEnrich.Select(item => item.Id)], token, progress));
        }

        return new ImportResultDto(parsed.Count, toAdd.Count, duplicateCount, list?.Id, list?.Name, skippedTitles);
    }

    /// <summary>
    /// Rows worth a background lookup: an AniList-profile import already carries cover, synopsis and
    /// genres, so queueing it would only burn a pass. MangaLib / Custom / MAL / Goodreads / Steam rows
    /// are missing at least one of those three, which is what the job is for.
    /// </summary>
    private static bool NeedsEnrichment(MediaItem item) =>
        string.IsNullOrWhiteSpace(item.CoverUrl)
        || MediaMetadataApplier.IsExternalUrl(item.CoverUrl)
        || string.IsNullOrWhiteSpace(item.Description)
        || string.IsNullOrWhiteSpace(item.Genres);

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

        if (string.IsNullOrWhiteSpace(existing.Genres))
        {
            var healedGenres = GenreNormalizer.NormalizeToCommaString(parsed.Genres);
            if (healedGenres is not null)
            {
                existing.Genres = healedGenres;
                modified = true;
            }
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

        if (string.IsNullOrWhiteSpace(existing.ImportSource) && !string.IsNullOrWhiteSpace(parsed.ExternalSource))
        {
            existing.ImportSource = parsed.ExternalSource;
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
            "manga" => new Manga { Title = dto.Title, Author = dto.Author, RomajiTitle = dto.RomajiTitle ?? MediaTitleHelper.ExtractLatinFromTitle(dto.Title), TotalChapters = dto.TotalCount is > 0 ? dto.TotalCount : null, CurrentChapter = Math.Max(0, dto.CurrentProgress ?? 0), CurrentVolume = Math.Max(0, dto.CurrentVolumes ?? 0), TotalVolumes = dto.TotalVolumes is > 0 ? dto.TotalVolumes : null },
            "game" => new VideoGame { Title = dto.Title, Platform = dto.Platform ?? "PC", Studio = dto.Studio, HoursPlayed = Math.Max(0, dto.CurrentProgress ?? 0) },
            "anime" => CreateAnime(dto),
            "movie" => new Movie { Title = dto.Title, Studio = dto.Studio, Director = dto.Director, RomajiTitle = dto.RomajiTitle ?? MediaTitleHelper.ExtractLatinFromTitle(dto.Title), DurationMinutes = dto.DurationMinutes ?? 0 },
            "tvshow" => new TvShow { Title = dto.Title, Studio = dto.Studio, RomajiTitle = dto.RomajiTitle ?? MediaTitleHelper.ExtractLatinFromTitle(dto.Title), EpisodeDurationMinutes = dto.DurationMinutes is > 0 ? dto.DurationMinutes : null },
            _ => throw new FormatException($"Unsupported media type: {dto.Type}")
        };
        item.SetStatus(dto.Status);
        item.Score = dto.Score is >= 1 and <= 10 ? dto.Score : null;
        item.CoverUrl = dto.CoverUrl;
        item.Description = dto.Description;
        item.Genres = GenreNormalizer.NormalizeToCommaString(dto.Genres) ?? item.Genres;
        var parsedReleaseDate = ParseDate(dto.ReleaseDate);
        item.SetReleaseDate(parsedReleaseDate, dto.ReleaseYear ?? ParseYear(dto.ReleaseDate));
        item.EndDate = ParseDate(dto.EndDate);
        item.ReleaseStatus = !string.IsNullOrWhiteSpace(dto.ReleaseStatus)
            ? dto.ReleaseStatus
            : ReleaseStatusRules.FromDates(item.ReleaseDate, item.EndDate);
        item.ExternalId = dto.ExternalId;
        item.ExternalSource = dto.ExternalSource;
        item.ImportSource = dto.ExternalSource;
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
            RomajiTitle = dto.RomajiTitle ?? MediaTitleHelper.ExtractLatinFromTitle(dto.Title),
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
            ? JsonSerializer.Serialize(new List<MediaRatingSerializer.MediaRatingRow> { new(src, score, votes.Value) }, AppJsonSerializerContext.Default.ListMediaRatingRow)
            : JsonSerializer.Serialize(new List<MediaRatingSerializer.MediaRatingRow> { new(src, score, null) }, AppJsonSerializerContext.Default.ListMediaRatingRow);
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
        Book => "book",
        Manga => "manga",
        VideoGame => "game",
        Movie movie when movie.IsAnime => "anime",
        TvShow show when show.IsAnime => "anime",
        Movie => "movie",
        TvShow => "tvshow",
        _ => ""
    };
}
