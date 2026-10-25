using System.Text.RegularExpressions;

namespace MediaTracker.Server.Features.Media.Import;

public static partial class MediaTitleHelper
{
    [GeneratedRegex(@"\(([^)]*[a-zA-Z]{2,}[^)]*)\)")]
    private static partial Regex ParenthesesLatinRegex();

    [GeneratedRegex(@"^([^\(]+)\s*\([^)]*[a-zA-Z][^)]*\)")]
    private static partial Regex CleanCyrillicPrefixRegex();

    public static bool IsLatin(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Any(char.IsLetter)
        && !value.Any(c => char.IsBetween(c, '\u0400', '\u04FF'));

    public static bool IsCyrillic(string? value) =>
        !string.IsNullOrWhiteSpace(value)
        && value.Any(c => char.IsBetween(c, '\u0400', '\u04FF'));

    public static string? ExtractLatinFromTitle(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;
        if (IsLatin(title)) return title.Trim();

        var match = ParenthesesLatinRegex().Match(title);
        if (match.Success)
        {
            var candidate = match.Groups[1].Value.Trim();
            if (IsLatin(candidate)) return candidate;
        }

        var parts = title.Split(new[] { " / ", " | ", " — ", " - " }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var part in parts)
        {
            var trimmed = part.Trim();
            if (IsLatin(trimmed)) return trimmed;
        }

        return null;
    }

    public static string CleanRussianTitle(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return string.Empty;
        var match = CleanCyrillicPrefixRegex().Match(title);
        if (match.Success)
        {
            var candidate = match.Groups[1].Value.Trim();
            if (IsCyrillic(candidate)) return candidate;
        }

        var parts = title.Split(new[] { " / ", " | " }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length > 1 && IsCyrillic(parts[0]))
        {
            return parts[0].Trim();
        }

        return title.Trim();
    }
}
