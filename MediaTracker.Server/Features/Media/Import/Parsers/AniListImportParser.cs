using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Entities;
using Serilog;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

/// <summary>
/// AniList export files (animelist.json / mangalist.json) and the public GraphQL MediaListCollection
/// response both reduce to the same entry shape (a list row with an optional "media" node), so one
/// mapper covers the file and the profile-by-username flows.
/// </summary>
public static class AniListImportParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string json, bool mangaFile)
    {
        using var document = JsonDocument.Parse(json);
        var entries = CollectEntries(document.RootElement);
        var results = new List<ParsedMediaItemDto>(entries.Count);

        foreach (var entry in entries)
        {
            try
            {
                var item = MapEntry(entry, mangaFile);
                if (!string.IsNullOrWhiteSpace(item.Title))
                {
                    results.Add(item);
                }
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Failed to parse AniList entry, skipping");
            }
        }

        return results;
    }

    /// <summary>Unwraps the GraphQL envelope (data → MediaListCollection → lists[].entries[]) and
    /// flattens every list into one entry sequence; a plain export array passes through as-is.</summary>
    private static List<JsonElement> CollectEntries(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array) return [.. root.EnumerateArray()];
        if (root.ValueKind != JsonValueKind.Object) throw new FormatException("AniList JSON must contain a list of entries.");
        if (root.TryGetProperty("errors", out var errors))
        {
            var msg = ErrorMessage(errors);
            throw new FormatException(msg is not null ? $"AniList error: {msg}" : "AniList returned an error.");
        }
        // A null collection means the user simply has no list of that type, not a malformed response.
        if (root.TryGetProperty("data", out var data))
            return data.ValueKind == JsonValueKind.Null ? [] : CollectEntries(data);
        if (root.TryGetProperty("MediaListCollection", out var collection))
            return collection.ValueKind == JsonValueKind.Null ? [] : CollectEntries(collection);
        if (root.TryGetProperty("lists", out var lists) && lists.ValueKind == JsonValueKind.Array)
            return [.. lists.EnumerateArray()
                .Where(list => list.ValueKind == JsonValueKind.Object && list.TryGetProperty("entries", out var e) && e.ValueKind == JsonValueKind.Array)
                .SelectMany(list => list.GetProperty("entries").EnumerateArray())];
        // A combined export puts the anime and manga lists side by side under their own keys; the
        // per-entry media.type still decides the type, so flattening every array is enough.
        var namedLists = root.EnumerateObject().Where(property => property.Value.ValueKind == JsonValueKind.Array).Select(property => property.Value).ToArray();
        if (namedLists.Length > 0) return [.. namedLists.SelectMany(list => list.EnumerateArray())];
        throw new FormatException("AniList JSON must contain a list of entries.");
    }

    private static string? ErrorMessage(JsonElement errors) =>
        errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() > 0
        && errors[0].ValueKind == JsonValueKind.Object && errors[0].TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String
        ? message.GetString()
        : null;

    private static ParsedMediaItemDto MapEntry(JsonElement entry, bool mangaFile)
    {
        var media = entry.TryGetProperty("media", out var nested) && nested.ValueKind == JsonValueKind.Object ? nested : entry;
        string? Value(JsonElement node, string key) =>
            node.ValueKind == JsonValueKind.Object && node.TryGetProperty(key, out var field) && field.ValueKind != JsonValueKind.Null
                ? field.ValueKind == JsonValueKind.String ? field.GetString()?.Trim() : field.ToString()?.Trim()
                : null;
        double? Number(JsonElement node, string key) => double.TryParse(Value(node, key), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) ? number : null;
        int? Whole(JsonElement node, string key) => Number(node, key) is { } value ? (int)Math.Round(value) : null;

        var typeText = Value(media, "type") ?? Value(entry, "type");
        var isManga = mangaFile || typeText?.Equals("MANGA", StringComparison.OrdinalIgnoreCase) == true;
        // The export file calls it listStatus, GraphQL calls it status.
        var statusText = (Value(entry, "status") ?? Value(entry, "listStatus") ?? "").ToUpperInvariant();
        var status = statusText switch
        {
            "CURRENT" => MediaStatus.InProgress,
            "COMPLETED" => MediaStatus.Completed,
            "PAUSED" => MediaStatus.OnHold,
            "DROPPED" => MediaStatus.Dropped,
            _ => MediaStatus.Planned
        };
        var rawScore = Number(entry, "score");
        int? score = rawScore is null or 0
            ? null
            : Math.Clamp((int)Math.Round(rawScore.Value > 10 ? rawScore.Value / 10.0 : rawScore.Value), 1, 10);

        var coverUrl = ExtractCover(media);
        var description = CleanDescription(Value(media, "description"));
        var genres = ExtractGenres(media);
        var releaseDate = ExtractDate(media, "startDate");
        var endDate = ExtractDate(media, "endDate");
        var releaseStatus = Value(media, "status");
        var romajiTitle = TitlePart(media, "romaji");
        var originalTitle = TitlePart(media, "native");
        var author = isManga ? ExtractAuthor(media) : null;
        var studio = !isManga ? ExtractStudio(media) : null;
        var avgScore = Number(media, "averageScore");
        double? rating = avgScore is > 0 ? Math.Round(avgScore.Value / 10.0, 1) : null;
        int? duration = Whole(media, "duration");
        int? releaseYear = ParseYear(releaseDate);

        return new ParsedMediaItemDto(
            Title: Title(media),
            Type: isManga ? "manga" : "anime",
            Status: status,
            Score: score,
            CurrentProgress: Whole(entry, "progress"),
            TotalCount: Whole(media, isManga ? "chapters" : "episodes"),
            Author: author,
            ReleaseYear: releaseYear,
            ExternalId: Value(media, "id"),
            ExternalSource: "AniList",
            CoverUrl: coverUrl,
            Description: description,
            Genres: genres,
            ReleaseDate: releaseDate,
            EndDate: endDate,
            ReleaseStatus: releaseStatus,
            RomajiTitle: romajiTitle,
            OriginalTitle: originalTitle,
            Rating: rating,
            Studio: studio,
            DurationMinutes: duration,
            CurrentVolumes: isManga ? Whole(entry, "progressVolumes") ?? Whole(entry, "volumes") : null,
            TotalVolumes: isManga ? Whole(media, "volumes") : null);
    }

    private static string Title(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object || !media.TryGetProperty("title", out var title)) return "";
        if (title.ValueKind == JsonValueKind.String) return title.GetString()?.Trim() ?? "";
        if (title.ValueKind != JsonValueKind.Object) return "";
        string? Named(string key) =>
            title.TryGetProperty(key, out var field) && field.ValueKind == JsonValueKind.String
                ? field.GetString()?.Trim()
                : null;
        var result = Named("english") ?? Named("romaji") ?? Named("native") ?? "";
        return string.IsNullOrWhiteSpace(result) ? "" : result;
    }

    private static string? TitlePart(JsonElement media, string part)
    {
        if (media.ValueKind != JsonValueKind.Object || !media.TryGetProperty("title", out var title)) return null;
        if (title.ValueKind == JsonValueKind.Object && title.TryGetProperty(part, out var field) && field.ValueKind == JsonValueKind.String)
        {
            var val = field.GetString();
            return string.IsNullOrWhiteSpace(val) ? null : val.Trim();
        }
        return null;
    }

    private static string? ExtractCover(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object) return null;
        if (media.TryGetProperty("coverImage", out var cover))
        {
            if (cover.ValueKind == JsonValueKind.Object)
            {
                var extra = String(cover, "extraLarge")?.Trim();
                var large = String(cover, "large")?.Trim();
                var med = String(cover, "medium")?.Trim();
                return !string.IsNullOrWhiteSpace(extra) ? extra : !string.IsNullOrWhiteSpace(large) ? large : !string.IsNullOrWhiteSpace(med) ? med : null;
            }
            if (cover.ValueKind == JsonValueKind.String)
            {
                var val = cover.GetString()?.Trim();
                return string.IsNullOrWhiteSpace(val) ? null : val;
            }
        }
        if (media.TryGetProperty("cover", out var c) && c.ValueKind == JsonValueKind.String)
        {
            var val = c.GetString()?.Trim();
            return string.IsNullOrWhiteSpace(val) ? null : val;
        }
        return null;
    }

    private static string? CleanDescription(string? desc)
    {
        if (string.IsNullOrWhiteSpace(desc)) return null;
        var text = Regex.Replace(desc, @"<br\s*/?>", "\n", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"<.*?>", string.Empty);
        text = global::System.Net.WebUtility.HtmlDecode(text).Trim();
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }

    private static string? ExtractGenres(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object) return null;
        if (media.TryGetProperty("genres", out var g))
        {
            if (g.ValueKind == JsonValueKind.Array)
            {
                var genres = g.EnumerateArray()
                    .Where(x => x.ValueKind == JsonValueKind.String)
                    .Select(x => x.GetString()?.Trim())
                    .Where(x => !string.IsNullOrWhiteSpace(x));
                var joined = string.Join(", ", genres);
                return string.IsNullOrWhiteSpace(joined) ? null : joined;
            }
            if (g.ValueKind == JsonValueKind.String)
            {
                var val = g.GetString()?.Trim();
                return string.IsNullOrWhiteSpace(val) ? null : val;
            }
        }
        return null;
    }

    private static string? ExtractDate(JsonElement node, string key)
    {
        if (node.ValueKind != JsonValueKind.Object || !node.TryGetProperty(key, out var prop)) return null;
        if (prop.ValueKind == JsonValueKind.String) return prop.GetString()?.Trim();
        if (prop.ValueKind == JsonValueKind.Number && prop.TryGetInt32(out var year)) return $"{year}";
        if (prop.ValueKind == JsonValueKind.Object) return FormatFuzzyDate(prop);
        return null;
    }

    private static string? FormatFuzzyDate(JsonElement dateNode)
    {
        if (dateNode.ValueKind != JsonValueKind.Object) return null;
        var year = Int(dateNode, "year");
        if (year is null or <= 0) return null;

        var month = Int(dateNode, "month");
        var day = Int(dateNode, "day");

        if (month is >= 1 and <= 12 && day is >= 1 and <= 31)
            return $"{year.Value:D4}-{month.Value:D2}-{day.Value:D2}";
        if (month is >= 1 and <= 12)
            return $"{year.Value:D4}-{month.Value:D2}";
        return $"{year.Value:D4}";
    }

    private static int? Int(JsonElement node, string key)
    {
        if (node.ValueKind != JsonValueKind.Object || !node.TryGetProperty(key, out var prop)) return null;
        if (prop.ValueKind == JsonValueKind.Number && prop.TryGetInt32(out var val)) return val;
        if (prop.ValueKind == JsonValueKind.String && int.TryParse(prop.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var strVal)) return strVal;
        return null;
    }

    private static int? ParseYear(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            return date.Year;
        return int.TryParse(value.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var yr) && yr > 0 ? yr : null;
    }

    private static string? ExtractStudio(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object) return null;
        if (media.TryGetProperty("studios", out var studios) && studios.ValueKind == JsonValueKind.Object)
        {
            if (studios.TryGetProperty("nodes", out var nodes) && nodes.ValueKind == JsonValueKind.Array)
            {
                foreach (var node in nodes.EnumerateArray())
                {
                    if (node.ValueKind == JsonValueKind.Object)
                    {
                        var name = String(node, "name")?.Trim();
                        if (!string.IsNullOrWhiteSpace(name)) return name;
                    }
                }
            }
        }
        return String(media, "studio")?.Trim();
    }

    private static string? ExtractAuthor(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object) return null;
        if (media.TryGetProperty("staff", out var staff) && staff.ValueKind == JsonValueKind.Object)
        {
            if (staff.TryGetProperty("edges", out var edges) && edges.ValueKind == JsonValueKind.Array)
            {
                string? firstFound = null;
                foreach (var edge in edges.EnumerateArray())
                {
                    if (edge.ValueKind != JsonValueKind.Object) continue;
                    var role = String(edge, "role") ?? "";
                    var node = edge.TryGetProperty("node", out var n) && n.ValueKind == JsonValueKind.Object ? n : default;
                    var nameObj = node.ValueKind == JsonValueKind.Object && node.TryGetProperty("name", out var nm) && nm.ValueKind == JsonValueKind.Object ? nm : default;
                    var fullName = String(nameObj, "full")?.Trim();
                    if (!string.IsNullOrWhiteSpace(fullName))
                    {
                        firstFound ??= fullName;
                        if (role.Contains("Story", StringComparison.OrdinalIgnoreCase) ||
                            role.Contains("Art", StringComparison.OrdinalIgnoreCase) ||
                            role.Contains("Original", StringComparison.OrdinalIgnoreCase))
                        {
                            return fullName;
                        }
                    }
                }
                if (firstFound is not null) return firstFound;
            }
        }
        return String(media, "author")?.Trim();
    }

    private static string? String(JsonElement node, string key) =>
        node.ValueKind == JsonValueKind.Object && node.TryGetProperty(key, out var field) && field.ValueKind == JsonValueKind.String
            ? field.GetString()
            : null;
}