using System.Text.Json;
using MediaTracker.Server.Common.Json;

namespace MediaTracker.Server.Features.Settings;

/// <summary>Reads the small JSON blobs the settings table stores, tolerating absent or corrupt rows.</summary>
public static class JsonSettings
{
    public static T? TryDeserialize<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return default;
        }

        try
        {
            return JsonSerializer.Deserialize(json, AppJsonSerializerContext.GetTypeInfo<T>());
        }
        catch (JsonException)
        {
            return default;
        }
    }

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, AppJsonSerializerContext.GetTypeInfo<T>());
}
