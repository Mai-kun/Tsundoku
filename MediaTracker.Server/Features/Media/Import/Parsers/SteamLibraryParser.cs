using System.Text.Json;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class SteamLibraryParser
{
    /// <summary>
    /// Parses a Steam library (GetOwnedGames answer or the same shape saved to a file).
    /// <paramref name="minPlaytimeMinutes"/> drops sub-<paramref name="minPlaytimeMinutes"/> entries —
    /// random launches and refund-bait whose only content is noise in the library list.
    /// </summary>
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string json, int minPlaytimeMinutes = 0)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.TryGetProperty("response", out var response) && response.TryGetProperty("games", out var responseGames)) root = responseGames;
        else if (root.TryGetProperty("games", out var games)) root = games;
        if (root.ValueKind != JsonValueKind.Array) throw new FormatException("Steam JSON must contain a games array.");
        return root.EnumerateArray()
            .Select(game => (minutes: Number(game, "playtime_forever") ?? Number(game, "playtimeForever") ?? Number(game, "minutesPlayed") ?? 0,
                dto: (game, name: String(game, "name") ?? String(game, "title") ?? "", appId: String(game, "appid") ?? String(game, "appId") ?? String(game, "id"))))
            .Select(entry =>
            {
                var (minutes, (game, name, appId)) = entry;
                var coverUrl = !string.IsNullOrWhiteSpace(appId)
                    ? $"https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/{appId}/library_600x900.jpg"
                    : null;
                return (minutes, item: new ParsedMediaItemDto(
                    Title: name,
                    Type: "game",
                    // A game never launched is a plan, not a playthrough; any played minute lands it
                    // in progress with the hours already on the row.
                    Status: minutes > 0 ? MediaStatus.InProgress : MediaStatus.Planned,
                    CurrentProgress: (int)Math.Min(minutes / 60, int.MaxValue),
                    ExternalId: appId,
                    ExternalSource: "Steam",
                    CoverUrl: coverUrl,
                    Platform: "PC"));
            })
            .Where(entry => !string.IsNullOrWhiteSpace(entry.item.Title))
            // Random launches and refund-bait: below the threshold they are only noise in the list.
            .Where(entry => entry.minutes >= minPlaytimeMinutes)
            .Select(entry => entry.item)
            .ToArray();
    }

    private static string? String(JsonElement el, string name) => el.TryGetProperty(name, out var v) ? v.ToString() : null;
    private static int? Number(JsonElement el, string name) => el.TryGetProperty(name, out var v) && v.TryGetInt32(out var n) ? n : null;
}
