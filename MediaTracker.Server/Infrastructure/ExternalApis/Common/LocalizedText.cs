namespace MediaTracker.Server.Infrastructure.ExternalApis.Common;

/// <summary>
/// Language-preference helpers shared by the providers that answer with a per-locale dictionary
/// (MangaDex's <c>title</c>/<c>description</c>, Kitsu's <c>titles</c>). Every provider used to grow
/// its own <c>if ru else if en</c> cascade; the preference order lives here so a change to it
/// (a new preferred locale, a system-language tiebreak) does not have to be replayed per provider.
/// </summary>
public static class LocalizedText
{
    /// <summary>
    /// The first non-empty value for a preferred language, in the order given. Falls through to the
    /// dictionary's own first value when none of the preferences are present, because a synopsis in
    /// an unlisted language still beats an empty field. Japanese originals are deliberately not
    /// handled here: <c>ja</c>/<c>ja-ro</c> map to OriginalTitle/RomajiTitle, which is a shape
    /// decision, not a preference order.
    /// </summary>
    public static string? Pick(IReadOnlyDictionary<string, string>? dict, params string[] preferredLanguages)
    {
        if (dict is null || dict.Count == 0)
        {
            return null;
        }

        foreach (var language in preferredLanguages)
        {
            if (!string.IsNullOrWhiteSpace(language)
                && dict.TryGetValue(language, out var value)
                && !string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return dict.Values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));
    }
}
