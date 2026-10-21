using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class MalJsonParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string json, bool mangaFile)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data)) root = data;
        if (root.ValueKind != JsonValueKind.Array) throw new FormatException("MAL JSON must contain a data array.");
        return root.EnumerateArray().Select(entry =>
        {
            var node = entry.TryGetProperty("node", out var nested) ? nested : entry;
            var list = entry.TryGetProperty("list_status", out var listStatus) ? listStatus : entry;
            string? Get(JsonElement value, string key) => value.TryGetProperty(key, out var field) ? field.ToString() : null;
            int? Number(JsonElement value, string key) => int.TryParse(Get(value, key), NumberStyles.Integer, CultureInfo.InvariantCulture, out var number) ? number : null;
            var isManga = mangaFile || node.TryGetProperty("num_chapters", out _) || node.TryGetProperty("num_volumes", out _);
            var statusText = (Get(list, "status") ?? "").ToLowerInvariant().Replace(' ', '_');
            var status = statusText switch
            {
                "watching" or "reading" => MediaStatus.InProgress,
                "completed" => MediaStatus.Completed,
                "on_hold" => MediaStatus.OnHold,
                "dropped" => MediaStatus.Dropped,
                _ => MediaStatus.Planned
            };
            var title = Get(node, "title") ?? Get(node, "title_english") ?? "";
            var progress = Number(list, isManga ? "num_chapters_read" : "num_episodes_watched");
            return new ParsedMediaItemDto(title, isManga ? "manga" : "anime", status,
                Number(list, "score") is > 0 and var score ? score : null,
                progress,
                Number(node, isManga ? "num_chapters" : "num_episodes"),
                ReleaseYear: ParseYear(Get(node, "start_date")),
                ExternalId: Get(node, "id"), ExternalSource: "mal",
                CurrentVolumes: isManga ? Number(list, "num_volumes_read") : null,
                TotalVolumes: isManga ? Number(node, "num_volumes") : null);
        }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();
    }

    private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, out var date)
        ? date.Year
        : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
}
