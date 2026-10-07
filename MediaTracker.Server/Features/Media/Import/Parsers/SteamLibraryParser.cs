using System.Text.Json;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.Import.Parsers;

public static class SteamLibraryParser
{
    public static IReadOnlyList<ParsedMediaItemDto> Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.TryGetProperty("response", out var response) && response.TryGetProperty("games", out var responseGames)) root = responseGames;
        else if (root.TryGetProperty("games", out var games)) root = games;
        if (root.ValueKind != JsonValueKind.Array) throw new FormatException("Steam JSON must contain a games array.");
        return root.EnumerateArray().Select(game =>
        {
            var name = String(game, "name") ?? String(game, "title") ?? "";
            var appId = String(game, "appid") ?? String(game, "appId") ?? String(game, "id");
            var minutes = Number(game, "playtime_forever") ?? Number(game, "playtimeForever") ?? Number(game, "minutesPlayed") ?? 0;
            return new ParsedMediaItemDto(name, "game", minutes > 0 ? MediaStatus.InProgress : MediaStatus.Planned,
                CurrentProgress: (int)Math.Min(minutes / 60, int.MaxValue), ExternalId: appId, ExternalSource: "steam");
        }).Where(item => !string.IsNullOrWhiteSpace(item.Title)).ToArray();
    }
    private static string? String(JsonElement el, string name) => el.TryGetProperty(name, out var v) ? v.ToString() : null;
    private static int? Number(JsonElement el, string name) => el.TryGetProperty(name, out var v) && v.TryGetInt32(out var n) ? n : null;
}
