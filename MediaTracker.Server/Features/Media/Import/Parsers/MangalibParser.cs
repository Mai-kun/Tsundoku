using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

/// <summary>
/// Parser for the SocialLib ecosystem (MangaLib, AnimeLib, RanobeLib, SlashLib / YaoiLib, HentaiLib).
/// Supports:
/// 1. api.cdnlibs.org JSON bookmark response (with nested 'media', 'item' / 'progress' and folder objects)
/// 2. Tsundoku instant collector flat JSON
/// 3. Old 'Lib to Shikimori' JSON / CSV exports
/// 4. Legacy MangaLib Tampermonkey CSV & flat JSON
/// </summary>
public static class MangalibParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string content, int? defaultSiteId = null, int? defaultStatusId = null)
    {
        var trimmed = content.TrimStart();
        if (trimmed.StartsWith('[') || trimmed.StartsWith('{'))
        {
            try
            {
                return ParseJson(trimmed, defaultSiteId, defaultStatusId);
            }
            catch (JsonException)
            {
                // Fall back to CSV if JSON parse fails
            }
        }

        return ParseCsv(content, defaultSiteId);
    }

    private static IReadOnlyList<ParsedMediaItemDto> ParseJson(string json, int? defaultSiteId, int? defaultStatusId = null)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (root.ValueKind == JsonValueKind.Object)
        {
            foreach (var wrapper in new[] { "data", "items", "list", "entries" })
            {
                if (root.TryGetProperty(wrapper, out var nested) && nested.ValueKind == JsonValueKind.Array)
                {
                    root = nested;
                    break;
                }
            }

            if (root.ValueKind != JsonValueKind.Array)
            {
                var single = MapJsonElement(root, defaultSiteId, defaultStatusId);
                return single is not null && !string.IsNullOrWhiteSpace(single.Title) ? [single] : [];
            }
        }

        if (root.ValueKind != JsonValueKind.Array)
            return [];

        return root.EnumerateArray()
            .Select(elem => MapJsonElement(elem, defaultSiteId, defaultStatusId))
            .Where(item => item is not null && !string.IsNullOrWhiteSpace(item.Title))
            .Select(item => item!)
            .ToArray();
    }

    private static ParsedMediaItemDto? MapJsonElement(JsonElement elem, int? defaultSiteId, int? defaultStatusId = null)
    {
        if (elem.ValueKind != JsonValueKind.Object) return null;

        var hasMedia = elem.TryGetProperty("media", out var media) && media.ValueKind == JsonValueKind.Object;
        var hasProgress = (elem.TryGetProperty("item", out var progress) && progress.ValueKind == JsonValueKind.Object)
                       || (elem.TryGetProperty("progress", out progress) && progress.ValueKind == JsonValueKind.Object);

        // Site ID & Media Type determination
        var siteId = GetJsonInt(elem, "site_id", "site")
            ?? (hasMedia ? GetJsonInt(media, "site_id", "site") : null)
            ?? defaultSiteId;

        var rawType = GetJsonString(elem, "type", "model")
            ?? (hasMedia ? GetJsonString(media, "model", "type") : null);

        var (type, source) = DetermineTypeAndSource(siteId, rawType);

        // Title & Romaji
        var rusName = GetJsonString(elem, "rus_name", "target_title_ru")
            ?? (hasMedia ? GetJsonString(media, "rus_name") : null);

        var altName = GetJsonString(elem, "name", "eng_name", "title", "target_title")
            ?? (hasMedia ? GetJsonString(media, "name", "eng_name", "title") : null);

        var title = !string.IsNullOrWhiteSpace(rusName) ? rusName : altName ?? "";
        var romaji = GetJsonString(elem, "eng_name", "target_title", "romaji", "romaji_name")
            ?? (hasMedia ? GetJsonString(media, "eng_name", "romaji") : null);

        // Status
        var statusName = GetJsonString(elem, "folder_name", "status_name")
            ?? (elem.TryGetProperty("folder", out var folderObj) && folderObj.ValueKind == JsonValueKind.Object ? GetJsonString(folderObj, "name") : null)
            ?? (elem.TryGetProperty("status", out var statusObj) && statusObj.ValueKind == JsonValueKind.Object ? GetJsonString(statusObj, "name") : null)
            ?? (elem.TryGetProperty("status", out var statusProp) && statusProp.ValueKind == JsonValueKind.String ? statusProp.GetString() : null);

        var rawCode = GetJsonString(elem, "folder_id", "status_id")
            ?? (elem.TryGetProperty("folder", out folderObj) && folderObj.ValueKind == JsonValueKind.Object ? GetJsonString(folderObj, "id") : null)
            ?? (elem.TryGetProperty("status", out statusObj) && statusObj.ValueKind == JsonValueKind.Object ? GetJsonString(statusObj, "id") : null)
            ?? GetJsonString(elem, "status");

        var status = MapStatus(statusName, rawCode, defaultStatusId);

        // Progress & Counts
        var progressNum = hasProgress ? GetJsonDouble(progress, "number", "chapter", "episode") : null;
        var progressFallback = GetJsonDouble(elem, "user_chapters", "read_chapters", "chapters_read", "chapter", "episodes_read", "episodes_watched", "progress");
        var currentProgress = progressNum.HasValue
            ? (int)Math.Floor(progressNum.Value)
            : (progressFallback.HasValue ? (int)Math.Floor(progressFallback.Value) : 0);

        var currentVol = hasProgress ? GetJsonInt(progress, "volume") : null;
        currentVol ??= GetJsonInt(elem, "volumes", "volume", "user_volumes");

        var total = hasMedia ? GetJsonInt(media, "chapters_count", "episodes_count", "chapters", "episodes") : null;
        total ??= GetJsonInt(elem, "chapters", "total_chapters", "episodes_count", "chapters_count", "episodes", "totalCount");

        // Score
        var scoreVal = GetJsonInt(elem, "user_rating", "rating", "score");
        var score = MapScore(scoreVal);

        // Cover
        var cover = ExtractJsonCover(elem) ?? (hasMedia ? ExtractJsonCover(media) : null);

        // Description, Genres, Author
        var desc = GetJsonString(elem, "summary", "description", "desc", "синопсис", "описание")
            ?? (hasMedia ? GetJsonString(media, "summary", "description") : null);

        var genres = ExtractJsonList(elem, "genres", "genre", "жанры", "жанр")
            ?? (hasMedia ? ExtractJsonList(media, "genres", "genre") : null);

        var author = ExtractJsonList(elem, "author", "authors", "автор", "авторы", "artist")
            ?? (hasMedia ? ExtractJsonList(media, "authors", "author", "artist") : null);

        var extId = (hasMedia ? GetJsonString(media, "slug_url") : null)
            ?? GetJsonString(elem, "slug_url", "target_id")
            ?? (hasMedia ? GetJsonString(media, "id") : null)
            ?? GetJsonString(elem, "media_id", "id");

        return new ParsedMediaItemDto(
            Title: title,
            Type: type,
            Status: status,
            Score: score,
            CurrentProgress: currentProgress,
            TotalCount: total,
            Author: author,
            ExternalSource: source,
            ExternalId: extId,
            CoverUrl: cover,
            Description: desc,
            Genres: genres,
            RomajiTitle: romaji,
            CurrentVolumes: currentVol);
    }

    private static IReadOnlyList<ParsedMediaItemDto> ParseCsv(string csv, int? defaultSiteId) =>
        CsvHelperMini.ReadRecords(csv)
            .Select(row => MapCsvRow(row, defaultSiteId))
            .Where(item => !string.IsNullOrWhiteSpace(item.Title))
            .ToArray();

    private static ParsedMediaItemDto MapCsvRow(Dictionary<string, string> row, int? defaultSiteId)
    {
        var siteId = Number(row, "site_id", "site") ?? defaultSiteId;
        var rawType = Get(row, "type", "model");
        var (type, source) = DetermineTypeAndSource(siteId, rawType);

        var rusName = Get(row, "rus_name", "target_title_ru");
        var altName = Get(row, "name", "eng_name", "title", "target_title");
        var title = !string.IsNullOrWhiteSpace(rusName) ? rusName : altName;

        var statusName = Get(row, "folder_name", "status_name");
        var rawStatus = Get(row, "status", "folder_id", "status_id");
        var status = MapStatus(statusName, rawStatus);

        var progress = Number(row, "user_chapters", "read_chapters", "chapters_read", "chapter", "episodes_read", "episodes_watched", "progress");
        var currentVol = Number(row, "volumes", "volume", "user_volumes");
        var total = Number(row, "chapters", "total_chapters", "episodes_count", "chapters_count", "episodes");
        var score = MapScore(Number(row, "user_rating", "rating", "score"));

        var cover = NullIfEmpty(Get(row, "cover", "img", "poster", "thumbnail", "image", "cover_url"));
        var desc = NullIfEmpty(Get(row, "summary", "description", "desc", "синопсис", "описание"));
        var genres = NullIfEmpty(Get(row, "genres", "genre", "жанры", "жанр"));
        var author = NullIfEmpty(Get(row, "author", "authors", "автор", "авторы", "artist"));
        var romaji = NullIfEmpty(Get(row, "eng_name", "target_title", "romaji", "romaji_name"));
        var extId = NullIfEmpty(Get(row, "slug_url", "target_id", "media_id", "id"));

        return new ParsedMediaItemDto(
            Title: title,
            Type: type,
            Status: status,
            Score: score,
            CurrentProgress: progress ?? 0,
            TotalCount: total,
            Author: author,
            ExternalSource: source,
            ExternalId: extId,
            CoverUrl: cover,
            Description: desc,
            Genres: genres,
            RomajiTitle: romaji,
            CurrentVolumes: currentVol);
    }

    public static (string Type, string Source) DetermineTypeAndSource(int? siteId, string? rawType)
    {
        var normType = rawType?.Trim().ToLowerInvariant();

        if (siteId == 5 || normType == "anime")
            return ("anime", "AnimeLib");

        if (siteId == 3 || normType is "ranobe" or "book" or "novel")
            return ("book", "RanobeLib");

        if (siteId == 2)
            return ("manga", "SlashLib");

        if (siteId == 4)
            return ("manga", "HentaiLib");

        if (siteId == 1)
            return ("manga", "MangaLib");

        return ("manga", "MangaLib");
    }

    public static MediaStatus MapStatus(string? statusName, string? rawCodeOrStatus, int? defaultStatusId = null)
    {
        // 1. Check string status name first (status_name, folder_name, or if status was provided as text)
        if (!string.IsNullOrWhiteSpace(statusName))
        {
            var matched = MatchStatusWord(statusName);
            if (matched.HasValue) return matched.Value;
        }

        if (!string.IsNullOrWhiteSpace(rawCodeOrStatus))
        {
            var matched = MatchStatusWord(rawCodeOrStatus);
            if (matched.HasValue) return matched.Value;
        }

        // 2. Next check numeric codes
        var codeToTest = rawCodeOrStatus;
        if (string.IsNullOrWhiteSpace(codeToTest) && defaultStatusId.HasValue)
        {
            codeToTest = defaultStatusId.Value.ToString(CultureInfo.InvariantCulture);
        }

        if (!string.IsNullOrWhiteSpace(codeToTest) &&
            int.TryParse(codeToTest.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var code))
        {
            return code switch
            {
                1 => MediaStatus.InProgress,
                2 => MediaStatus.Planned,
                3 => MediaStatus.Dropped,
                4 or 5 => MediaStatus.Completed,
                6 => MediaStatus.OnHold,
                _ => MediaStatus.Planned
            };
        }

        return MediaStatus.Planned;
    }

    private static MediaStatus? MatchStatusWord(string text)
    {
        var s = text.Trim().ToLowerInvariant();
        if (s.Contains("читаю") || s.Contains("смотрю") || s == "reading" || s == "watching" || s == "in_progress" || s == "in progress")
            return MediaStatus.InProgress;
        if (s.Contains("план") || s.Contains("запланировано") || s.Contains("буду") || s == "planned")
            return MediaStatus.Planned;
        if (s.Contains("прочитано") || s.Contains("просмотрено") || s.Contains("любим") || s == "completed" || s == "finished" || s.Contains("favorite"))
            return MediaStatus.Completed;
        if (s.Contains("брошен") || s.Contains("удален") || s == "dropped")
            return MediaStatus.Dropped;
        if (s.Contains("жду") || s.Contains("ожида") || s.Contains("отложен") || s.Contains("hold") || s.Contains("pause"))
            return MediaStatus.OnHold;

        return null;
    }

    private static int? MapScore(int? value)
    {
        if (value is null or <= 0) return null;
        if (value.Value <= 10) return Math.Clamp(value.Value, 1, 10);
        if (value.Value <= 100) return Math.Clamp((int)Math.Round(value.Value / 10.0), 1, 10);
        return 10;
    }

    private static string? ExtractJsonCover(JsonElement elem)
    {
        foreach (var propName in new[] { "cover", "img", "poster", "thumbnail", "image", "cover_url" })
        {
            if (!elem.TryGetProperty(propName, out var prop)) continue;
            if (prop.ValueKind == JsonValueKind.String)
            {
                var str = prop.GetString();
                if (!string.IsNullOrWhiteSpace(str)) return str.Trim();
            }
            else if (prop.ValueKind == JsonValueKind.Object)
            {
                foreach (var sub in new[] { "default", "md", "thumbnail" })
                {
                    if (prop.TryGetProperty(sub, out var subProp) && subProp.ValueKind == JsonValueKind.String)
                    {
                        var str = subProp.GetString();
                        if (!string.IsNullOrWhiteSpace(str)) return str.Trim();
                    }
                }
            }
        }
        return null;
    }

    private static string? ExtractJsonList(JsonElement elem, params string[] propertyNames)
    {
        foreach (var propName in propertyNames)
        {
            if (!elem.TryGetProperty(propName, out var prop)) continue;
            if (prop.ValueKind == JsonValueKind.String)
            {
                var str = prop.GetString();
                if (!string.IsNullOrWhiteSpace(str)) return str.Trim();
            }
            else if (prop.ValueKind == JsonValueKind.Array)
            {
                var list = new List<string>();
                foreach (var item in prop.EnumerateArray())
                {
                    if (item.ValueKind == JsonValueKind.String)
                    {
                        var s = item.GetString();
                        if (!string.IsNullOrWhiteSpace(s)) list.Add(s.Trim());
                    }
                    else if (item.ValueKind == JsonValueKind.Object &&
                             item.TryGetProperty("name", out var nameProp) &&
                             nameProp.ValueKind == JsonValueKind.String)
                    {
                        var s = nameProp.GetString();
                        if (!string.IsNullOrWhiteSpace(s)) list.Add(s.Trim());
                    }
                }
                if (list.Count > 0) return string.Join(", ", list);
            }
        }
        return null;
    }

    private static string? GetJsonString(JsonElement elem, params string[] propertyNames)
    {
        foreach (var propName in propertyNames)
        {
            if (!elem.TryGetProperty(propName, out var prop)) continue;
            if (prop.ValueKind == JsonValueKind.String)
            {
                var s = prop.GetString();
                if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
            }
            else if (prop.ValueKind == JsonValueKind.Number)
            {
                return prop.ToString();
            }
        }
        return null;
    }

    private static int? GetJsonInt(JsonElement elem, params string[] propertyNames)
    {
        foreach (var propName in propertyNames)
        {
            if (!elem.TryGetProperty(propName, out var prop)) continue;
            if (prop.ValueKind == JsonValueKind.Number && prop.TryGetInt32(out var n)) return n;
            if (prop.ValueKind == JsonValueKind.String && int.TryParse(prop.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
                return parsed;
        }
        return null;
    }

    private static double? GetJsonDouble(JsonElement elem, params string[] propertyNames)
    {
        foreach (var propName in propertyNames)
        {
            if (!elem.TryGetProperty(propName, out var prop)) continue;
            if (prop.ValueKind == JsonValueKind.Number && prop.TryGetDouble(out var d)) return d;
            if (prop.ValueKind == JsonValueKind.String && double.TryParse(prop.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed))
                return parsed;
        }
        return null;
    }

    private static string? NullIfEmpty(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string Get(Dictionary<string, string> row, params string[] keys) =>
        keys.Select(key => row.GetValueOrDefault(key, "")).FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? "";

    private static int? Number(Dictionary<string, string> row, params string[] keys) =>
        int.TryParse(Get(row, keys), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : null;
}
