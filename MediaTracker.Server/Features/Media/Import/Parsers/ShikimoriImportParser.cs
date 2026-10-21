using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class ShikimoriImportParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data)) root = data;
        if (root.ValueKind != JsonValueKind.Array) throw new FormatException("Shikimori JSON must contain an array of list entries.");

        return root.EnumerateArray()
            .Select(MapEntry)
            .Where(item => !string.IsNullOrWhiteSpace(item.Title))
            .ToArray();
    }

    private static ParsedMediaItemDto MapEntry(JsonElement entry)
    {
        var target = entry.TryGetProperty("anime", out var a) ? a : entry.TryGetProperty("manga", out var m) ? m : entry;
        var isManga = entry.TryGetProperty("manga", out _) || (String(target, "kind") is "manga" or "manhwa" or "manhua" or "one_shot" or "doujin");
        var statusText = (String(entry, "status") ?? "").ToLowerInvariant();
        var status = statusText switch
        {
            "watching" or "reading" => MediaStatus.InProgress,
            "completed" => MediaStatus.Completed,
            "on_hold" => MediaStatus.OnHold,
            "dropped" => MediaStatus.Dropped,
            _ => MediaStatus.Planned
        };

        var rusName = String(target, "russian");
        var romajiName = String(target, "name");
        var title = !string.IsNullOrWhiteSpace(rusName) ? rusName : romajiName ?? "";
        var origName = String(target, "japanese") ?? romajiName;

        var cover = ExtractCover(target);
        var genres = ExtractGenres(target);
        var releaseDate = String(target, "aired_on");
        var endDate = String(target, "released_on");
        var releaseStatus = MapReleaseStatus(String(target, "status"));
        var rating = double.TryParse(String(target, "score"), NumberStyles.Float, CultureInfo.InvariantCulture, out var sc) && sc > 0
            ? Math.Round(sc, 1)
            : (double?)null;

        var progress = Number(entry, isManga ? "chapters" : "episodes");
        var total = Number(target, isManga ? "chapters" : "episodes");
        var currentVolumes = isManga ? Number(entry, "volumes") : null;
        var totalVolumes = isManga ? Number(target, "volumes") : null;
        var userScore = Number(entry, "score") is > 0 and var s ? Math.Clamp(s, 1, 10) : (int?)null;
        var description = CleanDescription(String(target, "description") ?? String(target, "description_html"));

        return new ParsedMediaItemDto(
            Title: title,
            Type: isManga ? "manga" : "anime",
            Status: status,
            Score: userScore,
            CurrentProgress: progress,
            TotalCount: total,
            ReleaseYear: ParseYear(releaseDate),
            ExternalId: String(target, "id"),
            ExternalSource: "shikimori",
            CoverUrl: cover,
            Description: description,
            Genres: genres,
            ReleaseDate: releaseDate,
            EndDate: endDate,
            ReleaseStatus: releaseStatus,
            RomajiTitle: romajiName,
            OriginalTitle: origName,
            Rating: rating,
            CurrentVolumes: currentVolumes,
            TotalVolumes: totalVolumes);
    }

    private static string? ExtractCover(JsonElement target)
    {
        if (target.TryGetProperty("image", out var image))
        {
            string? url = null;
            if (image.ValueKind == JsonValueKind.Object)
            {
                url = String(image, "original") ?? String(image, "preview");
            }
            else if (image.ValueKind == JsonValueKind.String)
            {
                url = image.GetString();
            }

            if (!string.IsNullOrWhiteSpace(url))
            {
                if (url.StartsWith('/')) return $"https://shikimori.io{url}";
                return url;
            }
        }
        return null;
    }

    private static string? ExtractGenres(JsonElement target)
    {
        if (target.TryGetProperty("genres", out var g) && g.ValueKind == JsonValueKind.Array)
        {
            var list = g.EnumerateArray()
                .Select(item =>
                {
                    if (item.ValueKind == JsonValueKind.Object)
                        return String(item, "russian") ?? String(item, "name");
                    if (item.ValueKind == JsonValueKind.String)
                        return item.GetString();
                    return null;
                })
                .Where(s => !string.IsNullOrWhiteSpace(s));
            var joined = string.Join(", ", list);
            return string.IsNullOrWhiteSpace(joined) ? null : joined;
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

    private static string? MapReleaseStatus(string? status) => (status ?? "").ToLowerInvariant() switch
    {
        "released" => "FINISHED",
        "ongoing" => "RELEASING",
        "anons" => "NOT_YET_RELEASED",
        _ => string.IsNullOrWhiteSpace(status) ? null : status
    };

    private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
        ? date.Year
        : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var yr) ? yr : null;

    private static string? String(JsonElement el, string key) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(key, out var v) ? v.ToString() : null;

    private static int? Number(JsonElement el, string key) =>
        int.TryParse(String(el, key), CultureInfo.InvariantCulture, out var n) ? n : null;
}
