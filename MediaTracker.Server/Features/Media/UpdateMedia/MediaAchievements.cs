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

    /// <summary>
    /// Union of the stored payload and an incoming batch of unlocked names, returned in the same
    /// JSON-array shape the column stores. The stored spellings win, so a name the user (or an
    /// earlier sync) already wrote is never rewritten by a differently-cased duplicate.
    /// </summary>
    public static string? MergeUnlocked(string? stored, IReadOnlyList<string> incoming)
    {
        if (incoming.Count == 0) return stored;

        var merged = new List<string>(ParseNames(stored).Values);
        foreach (var name in incoming)
        {
            if (!merged.Contains(name, StringComparer.OrdinalIgnoreCase))
            {
                merged.Add(name);
            }
        }

        return JsonSerializer.Serialize(merged, MediaTracker.Server.Common.Json.AppJsonSerializerContext.Default.ListString);
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
