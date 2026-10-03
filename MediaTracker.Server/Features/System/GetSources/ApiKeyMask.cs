namespace MediaTracker.Server.Features.System.GetSources;

/// <summary>Shows enough of a stored key to confirm it was saved, never enough to reuse it.</summary>
public static class ApiKeyMask
{
    public static string? Mask(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        return key.Length <= 8 ? new string('•', key.Length) : $"{key[..4]}••••••••{key[^4..]}";
    }
}
