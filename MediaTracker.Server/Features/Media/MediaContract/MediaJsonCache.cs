using System.Text.Json;

namespace MediaTracker.Server.Features.Media.MediaContract;

/// <summary>
/// Reads and writes the JSON blobs cached on a media row. Both directions live here because one slice
/// writes what another reads: if the two disagreed on casing, the detail screen would come back with an
/// empty tab and nothing in the logs to say why.
/// </summary>
public static class MediaJsonCache
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    public static string Serialize<T>(IReadOnlyList<T> value) => JsonSerializer.Serialize(value, Options);

    /// <summary>
    /// A blob that no longer parses reads as empty rather than throwing: the only sensible response is
    /// to refetch, and that fetch replaces the stored copy anyway.
    /// </summary>
    public static IReadOnlyList<T> Deserialize<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        try
        {
            return JsonSerializer.Deserialize<List<T>>(json, Options) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }
}