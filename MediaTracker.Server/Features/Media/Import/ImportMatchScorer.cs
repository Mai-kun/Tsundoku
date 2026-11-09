using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

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
public sealed record ScoredCandidate(ExternalMediaDto Candidate, int Score, bool HasContradiction = false);

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

    public static int ScoreCandidate(MediaItem item, ExternalMediaDto candidate) =>
        ScoreCandidate(item, candidate, out _);

    public static int ScoreCandidate(MediaItem item, ExternalMediaDto candidate, out bool hasContradiction)
    {
        hasContradiction = false;

        // Author Guard: If both specify author and they are incompatible, hard contradiction (score = 0)
        var rawItemAuthor = ItemAuthor(item);
        var candAuthorKnown = !string.IsNullOrWhiteSpace(candidate.Author) || !string.IsNullOrWhiteSpace(candidate.Studio);
        if (!string.IsNullOrWhiteSpace(rawItemAuthor) && candAuthorKnown && !AuthorMatches(item, candidate))
        {
            hasContradiction = true;
        }

        // Year Guard: If release year difference exceeds 3 years and not 100% title match, hard contradiction (score = 0)
        if (item.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
        {
            var yearDiff = Math.Abs(item.ReleaseYear.Value - candidate.ReleaseYear.Value);
            if (yearDiff > 3 && !Is100PercentTitleMatch(item, candidate))
            {
                hasContradiction = true;
            }
        }

        // Isolation Guard: classic books must not match Asian light novel/manga providers unless 100% title and author match
        if (MediaMerger.IsClassicBook(item) && MediaMerger.IsAsianNovelOrMangaSource(candidate.ExternalSource))
        {
            if (!Is100PercentTitleMatch(item, candidate) || !AuthorMatches(item, candidate))
            {
                hasContradiction = true;
            }
        }

        if (hasContradiction)
        {
            return 0;
        }

        int best = 0;

        // Every stored name against every source name, so a romaji row can match an English hit and
        // vice versa; the title heuristics take the single best pair rather than stacking.
        foreach (var itemName in ItemTitles(item))
        {
            if (string.IsNullOrWhiteSpace(itemName)) continue;
            foreach (var candName in CandidateTitles(candidate))
            {
                if (string.IsNullOrWhiteSpace(candName)) continue;
                var score = TitlePairScore(itemName, candName);
                if (score > best)
                {
                    best = score;
                }
            }
        }

        // Direct search result base score >= 40% (eliminates false 0% for API matches with shared query tokens)
        if (best == 0 && HasDirectQueryMatch(item, candidate))
        {
            best = SimilarTitleBonus;
        }

        if (best == 0)
        {
            return 0;
        }

        var total = best;

        // 1. Release Year
        if (item.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
        {
            var diff = Math.Abs(item.ReleaseYear.Value - candidate.ReleaseYear.Value);
            if (diff <= 1)
            {
                total += SameYearBonus;
            }
            else if (diff > 3)
            {
                total -= DivergentYearPenalty;
            }
            else
            {
                total -= DivergentYearPenalty;
            }
        }
        else if (best >= ExactTitleBonus)
        {
            total += SameYearBonus;
        }

        // 2. Author / Studio
        if (!string.IsNullOrWhiteSpace(rawItemAuthor) && candAuthorKnown)
        {
            var authorMatches = AuthorMatches(item, candidate);
            if (authorMatches)
            {
                total += AuthorBonus;
            }
            else
            {
                hasContradiction = true;
                return 0;
            }
        }
        else if (best >= ExactTitleBonus)
        {
            total += AuthorBonus;
        }

        // 3. Chapter / Page / Episode Counts
        var itemCount = ItemCount(item);
        var candCount = CandidateCount(candidate);
        if (itemCount is > 0 && candCount is > 0)
        {
            var minCount = Math.Min(itemCount.Value, candCount.Value);
            var maxCount = Math.Max(itemCount.Value, candCount.Value);
            var ratio = minCount / (double)maxCount;
            if (ratio >= 0.8)
            {
                total += LengthBonus;
            }
            else if (ratio < 0.6)
            {
                total -= 30;
                hasContradiction = true;
            }
        }
        else if (best >= ExactTitleBonus)
        {
            total += LengthBonus;
        }

        // 4. Format / Country Mismatch (manhwa vs manga / KR vs JP)
        var itemFormat = ResolveItemMangaFormat(item);
        var candFormat = ResolveCandidateMangaFormat(candidate);
        var formatMismatch = (itemFormat is "manhwa" && candFormat is "manga")
                          || (itemFormat is "manga" && candFormat is "manhwa");

        if (!formatMismatch && !string.IsNullOrWhiteSpace(item.CountryOfOrigin) && !string.IsNullOrWhiteSpace(candidate.CountryOfOrigin))
        {
            var itemCountry = item.CountryOfOrigin.Trim().ToUpperInvariant();
            var candCountry = candidate.CountryOfOrigin.Trim().ToUpperInvariant();
            if ((itemCountry == "KR" && candCountry == "JP") || (itemCountry == "JP" && candCountry == "KR"))
            {
                formatMismatch = true;
            }
        }

        if (formatMismatch)
        {
            total -= 20;
            hasContradiction = true;
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
            .Select(candidate =>
            {
                var score = ScoreCandidate(item, candidate, out var hasContradiction);
                return new ScoredCandidate(candidate, score, hasContradiction);
            })
            .ToList();

        // Победа приоритетного источника при автовыборе: кандидат из первого источника в
        // настройках (например, AniList) с надёжным баллом (>= 60) автоматически побеждает любого
        // кандидата из более низких источников (например, Shikimori), если удовлетворяет защитному барьеру.
        if (topSource is not null)
        {
            var primary = scored
                .Where(scored => string.Equals(scored.Candidate.ExternalSource, topSource, StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(scored => scored.Score)
                .FirstOrDefault();
            if (primary is not null && primary.Score >= ConfidentAloneScore && CanAutoMatch(item, primary) && !HasHomonymConflict(primary, scored))
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
                var winnerScored = ranked[0].Candidate == tieBroken ? ranked[0] : ranked[1];
                if (CanAutoMatch(item, winnerScored) && !HasHomonymConflict(winnerScored, scored))
                {
                    return MatchVerdict.Confident(tieBroken);
                }
            }

            return MatchVerdict.Ambiguous([.. ranked.Take(12).Select(scored => scored.Candidate)]);
        }

        var aloneButStrong = best.Score >= ConfidentAloneScore && best.Score - runnerUp >= NearMissGap;
        if ((best.Score >= ConfidentScore || aloneButStrong) && CanAutoMatch(item, best) && !HasHomonymConflict(best, scored))
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

        var similarity = CalculateTitleSimilarity(a, b);
        if (similarity >= 0.88)
        {
            return SimilarTitleBonus;
        }

        var longer = Math.Max(a.Length, b.Length);
        var shorter = Math.Min(a.Length, b.Length);
        if (longer >= 5 && shorter >= 5 && (a.Contains(b, StringComparison.Ordinal) || b.Contains(a, StringComparison.Ordinal)))
        {
            // Complete containment of one name in the other: only if remainder is chapter/volume noise
            if (IsNoiseOnlyDifference(a, b))
            {
                return SimilarTitleBonus;
            }
        }

        if (WordOverlap(itemTitle!, candidateTitle!) >= 0.8 && similarity >= 0.70)
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
        var list = new List<string>();
        var span = value.AsSpan();
        var start = 0;
        for (var i = 0; i <= span.Length; i++)
        {
            if (i == span.Length || span[i] == ' ')
            {
                var token = span[start..i].Trim();
                if (!token.IsEmpty && token.Length >= 2)
                {
                    list.Add(token.ToString().ToLowerInvariant());
                }
                start = i + 1;
            }
        }
        return list;
    }

    private static bool HasDirectQueryMatch(MediaItem item, ExternalMediaDto candidate)
    {
        foreach (var itemName in ItemTitles(item))
        {
            if (string.IsNullOrWhiteSpace(itemName)) continue;
            var itemTokens = Tokens(itemName);
            if (itemTokens.Count == 0) continue;

            foreach (var candName in CandidateTitles(candidate))
            {
                if (string.IsNullOrWhiteSpace(candName)) continue;

                // Subtitle split: if candidate has a colon/dash/slash, check base title
                var splitIdx = candName.IndexOfAny([':', '—', '–', '/']);
                if (splitIdx > 0)
                {
                    var baseTitle = candName[..splitIdx].Trim();
                    var baseNorm = NormalizeTitle(baseTitle);
                    var itemNorm = NormalizeTitle(itemName);
                    if (baseNorm is not null && itemNorm is not null && baseNorm == itemNorm)
                    {
                        return true;
                    }
                }

                var candTokens = Tokens(candName);
                if (candTokens.Count == 0) continue;

                var maxTokens = Math.Max(itemTokens.Count, candTokens.Count);
                var sharedCount = itemTokens.Count(t => t.Length >= 3 && candTokens.Contains(t));
                if (sharedCount >= 2 && (sharedCount / (double)itemTokens.Count) >= 0.8)
                {
                    if (splitIdx < 0 && (candTokens.Count - sharedCount) > 1)
                    {
                        continue;
                    }

                    var sim = CalculateTitleSimilarity(itemName, candName);
                    if (sim >= 0.70 || splitIdx > 0)
                    {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    private static IEnumerable<string?> ItemTitles(MediaItem item)
    {
        var rawTitle = item.Title;
        var strippedTitle = MediaTitleHelper.StripGarbageSuffixes(rawTitle);

        yield return strippedTitle;
        if (!string.Equals(strippedTitle, rawTitle, StringComparison.Ordinal))
        {
            yield return rawTitle;
        }

        var romaji = item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        };
        if (!string.IsNullOrWhiteSpace(romaji))
        {
            yield return MediaTitleHelper.StripGarbageSuffixes(romaji);
        }

        if (!string.IsNullOrWhiteSpace(item.OriginalTitle))
        {
            yield return MediaTitleHelper.StripGarbageSuffixes(item.OriginalTitle);
        }

        if (!string.IsNullOrWhiteSpace(item.AltTitles))
        {
            foreach (var alt in MediaMetadataApplier.DeserializeAltTitles(item.AltTitles))
            {
                if (!string.IsNullOrWhiteSpace(alt))
                {
                    yield return MediaTitleHelper.StripGarbageSuffixes(alt);
                }
            }
        }

        var extractedLatin = MediaTitleHelper.ExtractLatinFromTitle(strippedTitle)
            ?? MediaTitleHelper.ExtractLatinFromTitle(rawTitle);
        if (!string.IsNullOrWhiteSpace(extractedLatin))
        {
            yield return MediaTitleHelper.StripGarbageSuffixes(extractedLatin);
        }

        var cleanedRussian = MediaTitleHelper.CleanRussianTitle(strippedTitle);
        if (!string.IsNullOrWhiteSpace(cleanedRussian) && cleanedRussian != strippedTitle)
        {
            yield return cleanedRussian;
        }
    }

    private static IEnumerable<string?> CandidateTitles(ExternalMediaDto candidate)
    {
        yield return MediaTitleHelper.StripGarbageSuffixes(candidate.Title);
        yield return MediaTitleHelper.StripGarbageSuffixes(candidate.RomajiTitle);
        yield return MediaTitleHelper.StripGarbageSuffixes(candidate.OriginalTitle);
        if (candidate.Synonyms is { Count: > 0 } synonyms)
        {
            foreach (var syn in synonyms)
            {
                if (!string.IsNullOrWhiteSpace(syn))
                {
                    yield return MediaTitleHelper.StripGarbageSuffixes(syn);
                }
            }
        }
    }

    private static string? ItemAuthor(MediaItem item) => item switch
    {
        Manga manga => manga.Author,
        Book book => book.Author,
        VideoGame game => game.Studio,
        Movie movie => movie.Studio,
        TvShow show => show.Studio,
        _ => null,
    };

    /// <summary>One human picks an adaptation by its author as often as by its name.</summary>
    private static bool AuthorMatches(MediaItem item, ExternalMediaDto candidate)
    {
        var rawAuthor = ItemAuthor(item);
        if (string.IsNullOrWhiteSpace(rawAuthor))
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(candidate.Author) && AreAuthorsCompatible(rawAuthor, candidate.Author))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(candidate.Studio) && AreAuthorsCompatible(rawAuthor, candidate.Studio))
        {
            return true;
        }

        return false;
    }

    private static bool HasSolidConfirmation(MediaItem item, ExternalMediaDto candidate)
    {
        if (AuthorMatches(item, candidate))
        {
            return true;
        }

        if (item.ReleaseYear is > 0 && candidate.ReleaseYear is > 0)
        {
            var yearDiff = Math.Abs(item.ReleaseYear.Value - candidate.ReleaseYear.Value);
            if (yearDiff <= 1)
            {
                return true;
            }
        }

        if (CountsAreClose(ItemCount(item), CandidateCount(candidate)))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(item.ExternalId) &&
            !string.IsNullOrWhiteSpace(candidate.ExternalId) &&
            string.Equals(item.ExternalId.Trim(), candidate.ExternalId.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            if (string.IsNullOrWhiteSpace(item.ExternalSource) ||
                string.IsNullOrWhiteSpace(candidate.ExternalSource) ||
                string.Equals(item.ExternalSource.Trim(), candidate.ExternalSource.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    internal static bool CanAutoMatch(MediaItem item, ScoredCandidate scored)
    {
        if (scored.HasContradiction || !HasSolidConfirmation(item, scored.Candidate))
        {
            return false;
        }

        // Substring containment without strict similarity must not auto-match
        var maxSim = MaxTitleSimilarity(item, scored.Candidate);
        if (maxSim < 0.88)
        {
            return false;
        }

        // Classic books must be isolated from Asian light novel/manga providers
        if (MediaMerger.IsClassicBook(item) && MediaMerger.IsAsianNovelOrMangaSource(scored.Candidate.ExternalSource))
        {
            if (!Is100PercentTitleMatch(item, scored.Candidate) || !AuthorMatches(item, scored.Candidate))
            {
                return false;
            }
        }

        return true;
    }

    public static bool AreAuthorsCompatible(string? authorA, string? authorB)
    {
        if (string.IsNullOrWhiteSpace(authorA) || string.IsNullOrWhiteSpace(authorB))
        {
            return true;
        }

        var a = authorA.Trim();
        var b = authorB.Trim();

        if (string.Equals(a, b, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var normA = NormalizeAuthorString(a);
        var normB = NormalizeAuthorString(b);
        if (normA == normB)
        {
            return true;
        }

        var latinA = RemoveDiacritics(TransliterateCyrillicToLatin(normA));
        var latinB = RemoveDiacritics(TransliterateCyrillicToLatin(normB));
        if (latinA == latinB)
        {
            return true;
        }

        var tokensA = GetAuthorTokens(latinA);
        var tokensB = GetAuthorTokens(latinB);

        if (tokensA.Count > 0 && tokensB.Count > 0)
        {
            var sharedSignificant = tokensA.Any(ta => ta.Length >= 4 && tokensB.Contains(ta));
            if (sharedSignificant)
            {
                return true;
            }

            var overlap = tokensA.Count(tokensB.Contains);
            if (overlap > 0 && (double)overlap / Math.Min(tokensA.Count, tokensB.Count) >= 0.5)
            {
                return true;
            }
        }

        return false;
    }

    private static string NormalizeAuthorString(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var c in value)
        {
            if (char.IsLetter(c) || c == ' ')
            {
                sb.Append(char.ToLowerInvariant(c));
            }
        }
        return sb.ToString().Trim();
    }

    private static List<string> GetAuthorTokens(string value)
    {
        var list = new List<string>();
        foreach (var part in value.Split([' ', ',', '.', '-', '_'], StringSplitOptions.RemoveEmptyEntries))
        {
            var t = part.Trim().ToLowerInvariant();
            if (t.Length > 1 && t is not "de" and not "van" and not "von" and not "der" and not "del" and not "la" and not "le" and not "де")
            {
                list.Add(t);
            }
        }
        return list;
    }

    public static string RemoveDiacritics(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(text.Length);
        foreach (var c in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
            {
                sb.Append(c);
            }
        }
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    public static string TransliterateCyrillicToLatin(string text)
    {
        var t = text.ToLowerInvariant();
        t = Regex.Replace(t, @"\bантуан\b", "antoine");
        t = Regex.Replace(t, @"\bсент\b", "saint");
        t = Regex.Replace(t, @"\bэкзюпери\b", "exupery");
        t = Regex.Replace(t, @"\bстивен\b", "stephen");
        t = Regex.Replace(t, @"\bкинг\b", "king");
        t = Regex.Replace(t, @"\bджон\b", "john");
        t = Regex.Replace(t, @"\bроулинг\b", "rowling");
        t = Regex.Replace(t, @"\bджордж\b", "george");
        t = Regex.Replace(t, @"\bоруэлл\b", "orwell");
        t = Regex.Replace(t, @"\bартур\b", "arthur");
        t = Regex.Replace(t, @"\bдоил\b", "doyle");
        t = Regex.Replace(t, @"\bдостоевск[а-я]*\b", "dostoevsky");
        t = Regex.Replace(t, @"\bтолст[а-я]*\b", "tolstoy");

        var sb = new StringBuilder(t.Length * 2);
        for (int i = 0; i < t.Length; i++)
        {
            char c = t[i];
            var mapped = c switch
            {
                'а' => "a", 'б' => "b", 'в' => "v", 'г' => "g", 'д' => "d",
                'е' or 'ё' => "e", 'ж' => "zh", 'з' => "z", 'и' => "i", 'й' => "y",
                'к' => "k", 'л' => "l", 'м' => "m", 'н' => "n", 'о' => "o",
                'п' => "p", 'р' => "r", 'с' => "s", 'т' => "t", 'у' => "u",
                'ф' => "f", 'х' => "kh", 'ц' => "ts", 'ч' => "ch", 'ш' => "sh",
                'щ' => "shch", 'ъ' or 'ь' => "", 'ы' => "y", 'э' => "e",
                'ю' => "yu", 'я' => "ya",
                _ => c.ToString()
            };
            sb.Append(mapped);
        }
        return sb.ToString();
    }

    public static double CalculateTitleSimilarity(string? titleA, string? titleB)
    {
        var a = NormalizeTitle(titleA);
        var b = NormalizeTitle(titleB);
        if (a is null || b is null) return 0.0;
        if (a == b) return 1.0;

        int maxLen = Math.Max(a.Length, b.Length);
        if (maxLen == 0) return 1.0;

        int distance = LevenshteinDistance(a, b);
        double levenshteinSim = 1.0 - (double)distance / maxLen;
        double diceSim = DiceCoefficient(a, b);

        return Math.Max(levenshteinSim, diceSim);
    }

    public static int LevenshteinDistance(string s, string t)
    {
        if (string.IsNullOrEmpty(s)) return t?.Length ?? 0;
        if (string.IsNullOrEmpty(t)) return s.Length;

        int n = s.Length;
        int m = t.Length;
        int[] d = new int[m + 1];

        for (int j = 0; j <= m; j++) d[j] = j;

        for (int i = 1; i <= n; i++)
        {
            int prevDiag = d[0];
            d[0] = i;
            char sc = s[i - 1];

            for (int j = 1; j <= m; j++)
            {
                int temp = d[j];
                int cost = sc == t[j - 1] ? 0 : 1;
                d[j] = Math.Min(Math.Min(d[j] + 1, d[j - 1] + 1), prevDiag + cost);
                prevDiag = temp;
            }
        }

        return d[m];
    }

    public static double DiceCoefficient(string s, string t)
    {
        if (s == t) return 1.0;
        if (s.Length < 2 || t.Length < 2) return 0.0;

        var sBigrams = new HashSet<int>(s.Length - 1);
        for (int i = 0; i < s.Length - 1; i++)
        {
            sBigrams.Add((s[i] << 16) | s[i + 1]);
        }

        int matches = 0;
        for (int i = 0; i < t.Length - 1; i++)
        {
            if (sBigrams.Contains((t[i] << 16) | t[i + 1]))
            {
                matches++;
            }
        }

        int maxBigrams = Math.Max(s.Length - 1, t.Length - 1);
        return maxBigrams > 0 ? (double)matches / maxBigrams : 0.0;
    }

    private static bool IsNoiseOnlyDifference(string a, string b)
    {
        var longer = a.Length >= b.Length ? a : b;
        var shorter = a.Length < b.Length ? a : b;

        var remainder = longer.Replace(shorter, string.Empty);
        if (remainder.Length == 0) return true;

        if (remainder.All(char.IsDigit)) return true;

        var cleaned = remainder;
        foreach (var noise in new[] { "chapter", "ch", "volume", "vol", "season", "episode", "ep", "part", "ova", "special" })
        {
            cleaned = cleaned.Replace(noise, string.Empty);
        }

        return cleaned.All(char.IsDigit);
    }

    public static bool Is100PercentTitleMatch(string? titleA, string? titleB)
    {
        if (string.IsNullOrWhiteSpace(titleA) || string.IsNullOrWhiteSpace(titleB)) return false;
        var a = NormalizeTitle(titleA);
        var b = NormalizeTitle(titleB);
        return a is not null && a == b;
    }

    public static bool Is100PercentTitleMatch(MediaItem item, ExternalMediaDto candidate)
    {
        foreach (var itemName in ItemTitles(item))
        {
            if (string.IsNullOrWhiteSpace(itemName)) continue;
            foreach (var candName in CandidateTitles(candidate))
            {
                if (string.IsNullOrWhiteSpace(candName)) continue;
                if (Is100PercentTitleMatch(itemName, candName)) return true;
            }
        }
        return false;
    }

    public static bool Is100PercentTitleMatch(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        var primaryTitles = new[] { primary.Title, primary.RomajiTitle, primary.OriginalTitle }
            .Concat(primary.Synonyms ?? [])
            .Where(t => !string.IsNullOrWhiteSpace(t));

        var fallbackTitles = new[] { fallback.Title, fallback.RomajiTitle, fallback.OriginalTitle }
            .Concat(fallback.Synonyms ?? [])
            .Where(t => !string.IsNullOrWhiteSpace(t));

        foreach (var pt in primaryTitles)
        {
            foreach (var ft in fallbackTitles)
            {
                if (Is100PercentTitleMatch(pt, ft)) return true;
            }
        }
        return false;
    }

    public static double MaxTitleSimilarity(MediaItem item, ExternalMediaDto candidate)
    {
        double max = 0.0;
        foreach (var it in ItemTitles(item))
        {
            if (string.IsNullOrWhiteSpace(it)) continue;
            foreach (var ct in CandidateTitles(candidate))
            {
                if (string.IsNullOrWhiteSpace(ct)) continue;
                var sim = CalculateTitleSimilarity(it, ct);
                if (sim > max) max = sim;
            }
        }
        return max;
    }

    public static double MaxTitleSimilarity(ExternalMediaDto primary, ExternalMediaDto fallback)
    {
        var primaryTitles = new[] { primary.Title, primary.RomajiTitle, primary.OriginalTitle }
            .Concat(primary.Synonyms ?? [])
            .Where(t => !string.IsNullOrWhiteSpace(t));

        var fallbackTitles = new[] { fallback.Title, fallback.RomajiTitle, fallback.OriginalTitle }
            .Concat(fallback.Synonyms ?? [])
            .Where(t => !string.IsNullOrWhiteSpace(t));

        double max = 0.0;
        foreach (var pt in primaryTitles)
        {
            foreach (var ft in fallbackTitles)
            {
                var sim = CalculateTitleSimilarity(pt, ft);
                if (sim > max) max = sim;
            }
        }
        return max;
    }

    private static bool HasHomonymConflict(ScoredCandidate target, IReadOnlyList<ScoredCandidate> allScored)
    {
        var targetNorm = NormalizeTitle(target.Candidate.Title) ?? NormalizeTitle(target.Candidate.RomajiTitle);
        if (targetNorm is null)
        {
            return false;
        }

        foreach (var other in allScored)
        {
            if (ReferenceEquals(target, other)) continue;
            if (other.Score < ReviewScore) continue;

            var otherNorm = NormalizeTitle(other.Candidate.Title) ?? NormalizeTitle(other.Candidate.RomajiTitle);
            if (otherNorm is null || targetNorm != otherNorm) continue;

            if (!AreMirroredCopies(target.Candidate, other.Candidate))
            {
                return true;
            }
        }

        return false;
    }

    private static bool AreMirroredCopies(ExternalMediaDto a, ExternalMediaDto b)
    {
        if (string.IsNullOrWhiteSpace(a.ExternalSource) ||
            string.IsNullOrWhiteSpace(b.ExternalSource) ||
            string.Equals(a.ExternalSource, b.ExternalSource, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var authorA = NormalizeTitle(a.Author) ?? NormalizeTitle(a.Studio);
        var authorB = NormalizeTitle(b.Author) ?? NormalizeTitle(b.Studio);
        if (authorA is not null && authorB is not null && authorA != authorB)
        {
            return false;
        }

        if (a.ReleaseYear is > 0 && b.ReleaseYear is > 0 && Math.Abs(a.ReleaseYear.Value - b.ReleaseYear.Value) > 1)
        {
            return false;
        }

        var formatA = ResolveCandidateMangaFormat(a);
        var formatB = ResolveCandidateMangaFormat(b);
        if ((formatA is "manhwa" && formatB is "manga") || (formatA is "manga" && formatB is "manhwa"))
        {
            return false;
        }

        return true;
    }

    private static string? ResolveItemMangaFormat(MediaItem item)
    {
        if (item is Manga manga && !string.IsNullOrWhiteSpace(manga.Format))
        {
            var f = manga.Format.Trim().ToLowerInvariant();
            if (f is "manhwa" or "manga" or "manhua" or "oel") return f;
        }

        if (!string.IsNullOrWhiteSpace(item.CountryOfOrigin))
        {
            return MangaFormats.FromCountryOfOrigin(item.CountryOfOrigin);
        }

        return null;
    }

    private static string? ResolveCandidateMangaFormat(ExternalMediaDto candidate)
    {
        if (!string.IsNullOrWhiteSpace(candidate.MangaFormat))
        {
            var mf = candidate.MangaFormat.Trim().ToLowerInvariant();
            if (mf is "manhwa" or "manga" or "manhua" or "oel") return mf;
        }

        if (!string.IsNullOrWhiteSpace(candidate.Format))
        {
            var f = candidate.Format.Trim().ToLowerInvariant();
            if (f is "manhwa" or "manga" or "manhua" or "oel") return f;
        }

        if (!string.IsNullOrWhiteSpace(candidate.CountryOfOrigin))
        {
            return MangaFormats.FromCountryOfOrigin(candidate.CountryOfOrigin);
        }

        return null;
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
