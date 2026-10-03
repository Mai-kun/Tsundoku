using System.Text.Json;

namespace MediaTracker.Server.Features.Media.UpdateMedia;

/// <summary>
/// Diffs two stored achievement payloads. Names are compared case-insensitively because the UI
/// toggles match that way; anything unparseable is treated as no change.
/// </summary>
public static class MediaAchievements
{
    public static IReadOnlyList<string> NewlyUnlocked(string? before, string? after)
    {
        if (string.Equals(before, after, StringComparison.Ordinal) || string.IsNullOrWhiteSpace(after))
        {
            return [];
        }

        var beforeNames = ParseNames(before);
        var afterNames = ParseNames(after);

        return afterNames
            .Where(pair => !beforeNames.ContainsKey(pair.Key))
            .Select(pair => pair.Value)
            .ToList();
    }

    private static Dictionary<string, string> ParseNames(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var element in document.RootElement.EnumerateArray())
            {
                var name = element.ToString();
                if (!string.IsNullOrWhiteSpace(name))
                {
                    result[name.Trim()] = name.Trim();
                }
            }

            return result;
        }
        catch (JsonException)
        {
            return [];
        }
    }
}
