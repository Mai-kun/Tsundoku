using System.Text;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.ExternalApis;

namespace MediaTracker.Server.Features.Media.Import;

public enum MatchVerdictKind
{
    Confident,
    Ambiguous,
    NoMatch,
}

/// <summary>
/// The decision the batch enrichment reached for one title: a single winner to auto-apply, a short
/// candidate list to put in front of the user, or nothing found at all.
/// </summary>
public sealed record MatchVerdict(
    MatchVerdictKind Kind,
    ExternalMediaDto? Winner,
    IReadOnlyList<ExternalMediaDto> Candidates)
{
    public static MatchVerdict Confident(ExternalMediaDto winner) =>
        new(MatchVerdictKind.Confident, winner, [winner]);

    public static MatchVerdict Ambiguous(IReadOnlyList<ExternalMediaDto> candidates) =>
        new(MatchVerdictKind.Ambiguous, null, candidates);

    public static MatchVerdict NoMatch() =>
        new(MatchVerdictKind.NoMatch, null, []);
}

/// <summary>
/// One found candidate plus the score it earned against the library row. Ranked by the scorer.
/// </summary>
public sealed record ScoredCandidate(ExternalMediaDto Candidate, int Score);

/// <summary>
/// Confidence scoring for library-match candidates. A title imported from a private list (MangaLib,
/// Custom CSV, MAL XML, Goodreads...) rarely carries ids for the aggregators, so the enrichment job
/// searches by name and this class decides whether one candidate is clearly the same work or the
/// row has to wait for the user's own verdict.
/// </summary>
public static class ImportMatchScorer
{
    /// <summary>Normalised exact-name hit.</summary>
    private const int ExactTitleBonus = 60;

    /// <summary>Partial-match hit (containment or a large word overlap).</summary>
    private const int SimilarTitleBonus = 40;

    private const int SameYearBonus = 20;

    private const int DivergentYearPenalty = 25;

    private const int AuthorBonus = 15;

    private const int LengthBonus = 10;

    private const int ConfidentScore = 75;

    private const int ConfidentAloneScore = 60;

    private const int ReviewScore = 30;

    private const int NearMissGap = 20;

    private const int TiedGap = 15;

    public static int ScoreCandidate(MediaItem item, ExternalMediaDto candidate)
    {
        int best = 0;

        ReadOnlySpan<string?> candTitles = [candidate.Title, candidate.RomajiTitle, candidate.OriginalTitle];

        // Every stored name against every source name, so a romaji row can match an English hit and
        // vice versa; the title heuristics take the single best pair rather than stacking.
        foreach (var itemName in ItemTitles(item))
        {
            if (string.IsNullOrWhiteSpace(itemName)) continue;
            foreach (var candName in candTitles)
            {
                if (string.IsNullOrWhiteSpace(candName)) continue;
                var score = TitlePairScore(itemName, candName);
                if (score > best)
                {
                    best = score;
                }
            }
        }

        if (best == 0)
        {
            return 0;
        }

        var total = best;

        if (item.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
        {
            var diff = Math.Abs(item.ReleaseYear.Value - candidate.ReleaseYear.Value);
            if (diff <= 1) total += SameYearBonus;
            else if (diff > 2) total -= DivergentYearPenalty;
        }

        if (AuthorMatches(item, candidate))
        {
            total += AuthorBonus;
        }

        if (CountsAreClose(ItemCount(item), CandidateCount(candidate)))
        {
            total += LengthBonus;
        }

        return Math.Clamp(total, 0, 100);
    }

    /// <summary>
    /// Ranks the candidates and classifies the outcome. Two equally scoring hits (an original and its
    /// adaptation, a spin-off with the same title) are exactly the case a lone best score would
    /// silently mis-pick, so a small gap between the top two always degrades to a review list —
    /// unless the two hits come from different sources and both matched reliably, in which case the
    /// user's source order is a safe tie-breaker and no manual review is needed.
    /// </summary>
    public static MatchVerdict EvaluateCandidates(
        MediaItem item,
        IReadOnlyList<ExternalMediaDto> candidates,
        IReadOnlyList<string>? sourcePriorities = null)
    {
        if (candidates.Count == 0)
        {
            return MatchVerdict.NoMatch();
        }

        var rankBySource = sourcePriorities is { Count: > 0 } ? BuildSourceRank(sourcePriorities) : null;
        var topSource = sourcePriorities is { Count: > 0 } ? sourcePriorities[0] : null;

        var scored = candidates
            .Select(candidate => new ScoredCandidate(candidate, ScoreCandidate(item, candidate)))
            .ToList();

        // Победа приоритетного источника при автовыборе: кандидат из первого источника в
        // настройках (например, AniList) с надёжным баллом (>= 60) автоматически побеждает любого
        // кандидата из более низких источников (например, Shikimori), даже если у того числовой
        // балл формально выше.
        if (topSource is not null)
        {
            var primary = scored
                .Where(scored => string.Equals(scored.Candidate.ExternalSource, topSource, StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(scored => scored.Score)
                .FirstOrDefault();
            if (primary is not null && primary.Score >= ConfidentAloneScore)
            {
                return MatchVerdict.Confident(primary.Candidate);
            }
        }

        // Строгая сортировка кандидатов: 1) индекс источника в sourcePriorities,
        // 2) внутри одного источника — по баллу совпадения.
        var ranked = scored
            .OrderBy(scored => rankBySource is not null && scored.Candidate.ExternalSource is not null && rankBySource.TryGetValue(scored.Candidate.ExternalSource, out var rank) ? rank : int.MaxValue)
            .ThenByDescending(scored => scored.Score)
            .ToList();

        var best = ranked[0];
        var runnerUp = ranked.Count > 1 ? ranked[1].Score : 0;

        if (best.Score < ReviewScore)
        {
            return MatchVerdict.NoMatch();
        }

        var beatenByPeers = best.Score - runnerUp < TiedGap;
        if (beatenByPeers)
        {
            var tieBroken = ranked.Count > 1
                ? BreakCrossSourceTie(ranked[0], ranked[1], sourcePriorities)
                : null;
            if (tieBroken is not null)
            {
                return MatchVerdict.Confident(tieBroken);
            }

            return MatchVerdict.Ambiguous([.. ranked.Take(12).Select(scored => scored.Candidate)]);
        }

        var aloneButStrong = best.Score >= ConfidentAloneScore && best.Score - runnerUp >= NearMissGap;
        if (best.Score >= ConfidentScore || aloneButStrong)
        {
            return MatchVerdict.Confident(best.Candidate);
        }

        return MatchVerdict.Ambiguous([.. ranked.Take(12).Select(scored => scored.Candidate)]);
    }

    private static Dictionary<string, int> BuildSourceRank(IReadOnlyList<string> sourcePriorities)
    {
        var rank = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < sourcePriorities.Count; i++)
        {
            rank.TryAdd(sourcePriorities[i], i);
        }

        return rank;
    }

    /// <summary>
    /// Two hits from two different sources that both scored high (both plausibly the same work) are
    /// resolved by the user's source priorities instead of a manual round. Same-source pairs keep
    /// going to review: one provider returning two titles is a data question, not an order question.
    /// </summary>
    private static ExternalMediaDto? BreakCrossSourceTie(
        ScoredCandidate first,
        ScoredCandidate second,
        IReadOnlyList<string>? sourcePriorities)
    {
        if (first.Score < ConfidentAloneScore || second.Score < ConfidentAloneScore)
        {
            return null;
        }

        if (string.Equals(first.Candidate.ExternalSource, second.Candidate.ExternalSource, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (sourcePriorities is null || sourcePriorities.Count == 0)
        {
            return null;
        }

        var rank = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < sourcePriorities.Count; i++)
        {
            rank.TryAdd(sourcePriorities[i], i);
        }

        var firstRank = first.Candidate.ExternalSource is null || !rank.TryGetValue(first.Candidate.ExternalSource, out var a) ? int.MaxValue : a;
        var secondRank = second.Candidate.ExternalSource is null || !rank.TryGetValue(second.Candidate.ExternalSource, out var b) ? int.MaxValue : b;

        return firstRank == secondRank ? null : firstRank < secondRank ? first.Candidate : second.Candidate;
    }

    /// <summary>Exact normalised hit beats a partial hit; the pair contributes the better one.</summary>
    internal static int TitlePairScore(string? itemTitle, string? candidateTitle)
    {
        var a = NormalizeTitle(itemTitle);
        var b = NormalizeTitle(candidateTitle);
        if (a is null || b is null)
        {
            return 0;
        }

        if (a == b)
        {
            return ExactTitleBonus;
        }

        var longer = Math.Max(a.Length, b.Length);
        var shorter = Math.Min(a.Length, b.Length);
        if (longer >= 5 && (a.Contains(b, StringComparison.Ordinal) || b.Contains(a, StringComparison.Ordinal)))
        {
            // Complete containment of one name in the other: "Клинок" inside "Клинок рассекающий...".
            // A 3-letter prefix inside a long name is noise, hence the length floor on the shorter side.
            if (shorter >= 5)
            {
                return SimilarTitleBonus;
            }
        }

        if (WordOverlap(itemTitle!, candidateTitle!) >= 0.8)
        {
            return SimilarTitleBonus;
        }

        return 0;
    }

    /// <summary>Lowercase letters and digits only: brackets, spaces and punctuation never match.</summary>
    internal static string? NormalizeTitle(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var builder = new StringBuilder(value.Length);
        foreach (var rawCh in value)
        {
            if (char.IsLetterOrDigit(rawCh))
            {
                builder.Append(char.ToLowerInvariant(rawCh));
            }
        }

        return builder.Length == 0 ? null : builder.ToString();
    }

    /// <summary>Share of the shorter title's words the other title also contains.</summary>
    private static double WordOverlap(string itemTitle, string candidateTitle)
    {
        var a = Tokens(itemTitle);
        var b = Tokens(candidateTitle);
        if (a.Count == 0 || b.Count == 0)
        {
            return 0;
        }

        var hits = 0;
        for (var i = 0; i < a.Count; i++)
        {
            if (b.Contains(a[i])) hits++;
        }
        return hits / (double)Math.Min(a.Count, b.Count);
    }

    private static List<string> Tokens(string value)
    {
        var parts = value.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var list = new List<string>(parts.Length);
        foreach (var part in parts)
        {
            if (part.Length >= 2)
            {
                list.Add(part.ToLowerInvariant());
            }
        }
        return list;
    }

    private static IEnumerable<string?> ItemTitles(MediaItem item)
    {
        yield return item.Title;
        yield return item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        };
        yield return item.OriginalTitle;

        var extractedLatin = MediaTitleHelper.ExtractLatinFromTitle(item.Title);
        if (!string.IsNullOrWhiteSpace(extractedLatin))
        {
            yield return extractedLatin;
        }

        var cleanedRussian = MediaTitleHelper.CleanRussianTitle(item.Title);
        if (!string.IsNullOrWhiteSpace(cleanedRussian) && cleanedRussian != item.Title)
        {
            yield return cleanedRussian;
        }
    }

    private static IEnumerable<string?> CandidateTitles(ExternalMediaDto candidate) =>
        [candidate.Title, candidate.RomajiTitle, candidate.OriginalTitle];

    /// <summary>One human picks an adaptation by its author as often as by its name.</summary>
    private static bool AuthorMatches(MediaItem item, ExternalMediaDto candidate)
    {
        var itemAuthor = item switch
        {
            Manga manga => manga.Author,
            Book book => book.Author,
            VideoGame game => game.Studio,
            Movie movie => movie.Studio,
            TvShow show => show.Studio,
            _ => null,
        };
        if (string.IsNullOrWhiteSpace(itemAuthor) || string.IsNullOrWhiteSpace(candidate.Studio) && string.IsNullOrWhiteSpace(candidate.Author))
        {
            return false;
        }

        var candAuthor = NormalizeTitle(candidate.Author) ?? NormalizeTitle(candidate.Studio);
        return candAuthor is not null && NormalizeTitle(itemAuthor) == candAuthor;
    }

    /// <summary>Chapters, pages or episodes; only titles of the same length get the bonus.</summary>
    private static bool CountsAreClose(int? itemCount, int? candidateCount)
    {
        if (itemCount is not > 0 || candidateCount is not > 0)
        {
            return false;
        }

        var ratio = Math.Min(itemCount.Value, candidateCount.Value) / (double)Math.Max(itemCount.Value, candidateCount.Value);
        return ratio >= 0.8;
    }

    private static int? ItemCount(MediaItem item) => item switch
    {
        Manga manga => manga.TotalChapters,
        Book book => book.TotalPages,
        TvShow show => show.Seasons?.Sum(season => season.TotalEpisodes) is int total && total > 0 ? total : null,
        _ => null,
    };

    private static int? CandidateCount(ExternalMediaDto candidate)
    {
        if (candidate.TotalCount is > 0)
        {
            return candidate.TotalCount;
        }

        if (candidate.Chapters is > 0)
        {
            return candidate.Chapters;
        }

        return candidate.Seasons is { Count: > 0 } seasons
            ? seasons.Select(season => season.TotalEpisodes).Where(count => count > 0).Sum()
            : null;
    }
}
