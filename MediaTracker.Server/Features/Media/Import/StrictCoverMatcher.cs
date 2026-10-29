using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.Media.Import;

public static partial class StrictCoverMatcher
{
    [GeneratedRegex(@"(?:season|сезон)\s*(\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex SeasonNumRegex();

    [GeneratedRegex(@"(\d+)(?:st|nd|rd|th)\s+(?:season|сезон)", RegexOptions.IgnoreCase)]
    private static partial Regex OrdinalSeasonRegex();

    [GeneratedRegex(@"(?:part|часть)\s*(\d+)", RegexOptions.IgnoreCase)]
    private static partial Regex PartNumRegex();

    [GeneratedRegex(@"\b(II|III|IV|V|VI|VII|VIII|IX|X)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RomanNumeralRegex();

    [GeneratedRegex(@"\b(\d+)\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex TrailingNumberRegex();

    public static bool IsStrictMatch(MediaItem item, ExternalMediaDto candidate)
    {
        // 1. General score must be >= 80
        if (ImportMatchScorer.ScoreCandidate(item, candidate) < 80)
        {
            return false;
        }

        // Must have at least one exact title pair hit (TitlePairScore == 60)
        if (!HasExactTitleMatch(item, candidate))
        {
            return false;
        }

        // 2. Season / part markers must match completely
        if (!SeasonMarkersMatch(item, candidate))
        {
            return false;
        }

        // 3. If both have known ReleaseYear, must match year-for-year
        if (item.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
        {
            if (item.ReleaseYear.Value != candidate.ReleaseYear.Value)
            {
                return false;
            }
        }

        return true;
    }

    private static bool HasExactTitleMatch(MediaItem item, ExternalMediaDto candidate)
    {
        string? itemRomaji = item switch
        {
            Manga m => m.RomajiTitle,
            Movie mov => mov.RomajiTitle,
            TvShow tv => tv.RomajiTitle,
            _ => null
        };

        ReadOnlySpan<string?> itemTitles = [item.Title, itemRomaji, item.OriginalTitle];
        ReadOnlySpan<string?> candTitles = [candidate.Title, candidate.RomajiTitle, candidate.OriginalTitle];

        foreach (var it in itemTitles)
        {
            if (string.IsNullOrWhiteSpace(it)) continue;
            foreach (var ct in candTitles)
            {
                if (string.IsNullOrWhiteSpace(ct)) continue;
                if (ImportMatchScorer.TitlePairScore(it, ct) == 60)
                {
                    return true;
                }
            }
        }

        return false;
    }

    public static bool SeasonMarkersMatch(MediaItem item, ExternalMediaDto candidate)
    {
        string? itemRomaji = item switch
        {
            Manga m => m.RomajiTitle,
            Movie mov => mov.RomajiTitle,
            TvShow tv => tv.RomajiTitle,
            _ => null
        };

        var itemMarker = ExtractSeasonMarker(item.Title)
            ?? ExtractSeasonMarker(itemRomaji)
            ?? ExtractSeasonMarker(item.OriginalTitle);

        var candMarker = ExtractSeasonMarker(candidate.Title)
            ?? ExtractSeasonMarker(candidate.RomajiTitle)
            ?? ExtractSeasonMarker(candidate.OriginalTitle);

        var normalizedItemMarker = itemMarker ?? 1;
        var normalizedCandMarker = candMarker ?? 1;

        return normalizedItemMarker == normalizedCandMarker;
    }

    public static int? ExtractSeasonMarker(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;

        var seasonMatch = SeasonNumRegex().Match(title);
        if (seasonMatch.Success && int.TryParse(seasonMatch.Groups[1].Value, out var sNum))
        {
            return sNum;
        }

        var ordMatch = OrdinalSeasonRegex().Match(title);
        if (ordMatch.Success && int.TryParse(ordMatch.Groups[1].Value, out var oNum))
        {
            return oNum;
        }

        var partMatch = PartNumRegex().Match(title);
        if (partMatch.Success && int.TryParse(partMatch.Groups[1].Value, out var pNum))
        {
            return pNum;
        }

        var romanMatch = RomanNumeralRegex().Match(title);
        if (romanMatch.Success)
        {
            var val = romanMatch.Groups[1].Value.ToUpperInvariant() switch
            {
                "II" => 2,
                "III" => 3,
                "IV" => 4,
                "V" => 5,
                "VI" => 6,
                "VII" => 7,
                "VIII" => 8,
                "IX" => 9,
                "X" => 10,
                _ => (int?)null
            };
            if (val.HasValue) return val.Value;
        }

        var trailingMatch = TrailingNumberRegex().Match(title);
        if (trailingMatch.Success && int.TryParse(trailingMatch.Groups[1].Value, out var tNum))
        {
            if (tNum is >= 2 and <= 20)
            {
                return tNum;
            }
        }

        return null;
    }
}
