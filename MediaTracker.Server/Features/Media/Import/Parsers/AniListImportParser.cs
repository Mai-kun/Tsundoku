using System.Globalization;
using System.Text.Json;
using MediaTracker.Server.Domain.Entities;

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
        return CollectEntries(document.RootElement)
            .Select(entry => MapEntry(entry, mangaFile))
            .Where(item => !string.IsNullOrWhiteSpace(item.Title))
            .ToArray();
    }

    /// <summary>Unwraps the GraphQL envelope (data → MediaListCollection → lists[].entries[]) and
    /// flattens every list into one entry sequence; a plain export array passes through as-is.</summary>
    private static List<JsonElement> CollectEntries(JsonElement root)
    {
        if (root.ValueKind == JsonValueKind.Array) return [.. root.EnumerateArray()];
        if (root.ValueKind != JsonValueKind.Object) throw new FormatException("AniList JSON must contain a list of entries.");
        if (root.TryGetProperty("errors", out var errors)) throw new FormatException(ErrorMessage(errors) ?? "AniList returned an error.");
        // A null collection means the user simply has no list of that type, not a malformed response.
        if (root.TryGetProperty("data", out var data))
            return data.ValueKind == JsonValueKind.Null ? [] : CollectEntries(data);
        if (root.TryGetProperty("MediaListCollection", out var collection))
            return collection.ValueKind == JsonValueKind.Null ? [] : CollectEntries(collection);
        if (root.TryGetProperty("lists", out var lists) && lists.ValueKind == JsonValueKind.Array)
            return [.. lists.EnumerateArray()
                .Where(list => list.TryGetProperty("entries", out _) && list.GetProperty("entries").ValueKind == JsonValueKind.Array)
                .SelectMany(list => list.GetProperty("entries").EnumerateArray())];
        // A combined export puts the anime and manga lists side by side under their own keys; the
        // per-entry media.type still decides the type, so flattening every array is enough.
        var namedLists = root.EnumerateObject().Where(property => property.Value.ValueKind == JsonValueKind.Array).Select(property => property.Value).ToArray();
        if (namedLists.Length > 0) return [.. namedLists.SelectMany(list => list.EnumerateArray())];
        throw new FormatException("AniList JSON must contain a list of entries.");
    }

    private static string? ErrorMessage(JsonElement errors) => errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() > 0
        && errors[0].ValueKind == JsonValueKind.Object && errors[0].TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String
        ? message.GetString()
        : null;

    private static ParsedMediaItemDto MapEntry(JsonElement entry, bool mangaFile)
    {
        var media = entry.TryGetProperty("media", out var nested) && nested.ValueKind == JsonValueKind.Object ? nested : entry;
        string? Value(JsonElement node, string key) => node.ValueKind == JsonValueKind.Object && node.TryGetProperty(key, out var field)
            ? field.ValueKind == JsonValueKind.String ? field.GetString() : field.ToString()
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
        return new ParsedMediaItemDto(Title(media), isManga ? "manga" : "anime", status, score,
            CurrentProgress: Whole(entry, "progress"),
            TotalCount: Whole(media, isManga ? "chapters" : "episodes"),
            ExternalId: Value(media, "id"), ExternalSource: "AniList");
    }

    private static string Title(JsonElement media)
    {
        if (media.ValueKind != JsonValueKind.Object || !media.TryGetProperty("title", out var title)) return "";
        if (title.ValueKind == JsonValueKind.String) return title.GetString() ?? "";
        string? Named(string key) => title.TryGetProperty(key, out var field) && field.ValueKind == JsonValueKind.String ? field.GetString() : null;
        return Named("english") ?? Named("romaji") ?? Named("native") ?? "";
    }
}