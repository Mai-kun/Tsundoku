using System.Text;
using System.Text.RegularExpressions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using Dapper;

namespace MediaTracker.Server.Infrastructure.Persistence.Franchises;

public interface IFranchiseService
{
    string? InferFranchiseName(string? title);
    string? ExtractBaseTitle(string? title);
    Task<int> AutoBackfillFranchisesAsync(AppDbContext db, CancellationToken ct = default);
    Task LinkFranchiseOnCreateAsync(AppDbContext db, MediaItem item, string? requestedFranchiseName, CancellationToken ct = default);
    Task LinkFranchiseOnUpdateAsync(AppDbContext db, MediaItem item, Guid? requestedFranchiseId, string? requestedFranchiseName, CancellationToken ct = default);
    Task<int> LinkGameSeriesAsync(AppDbContext db, MediaItem item, IReadOnlyList<ExternalRelationDto> series, CancellationToken ct = default);
}

/// <summary>
/// Groups library titles into franchises with a three-level matcher instead of the old single
/// regex: a related-media link is treated as proof, and titles without one are compared through
/// their cross-language base roots ("Бездомный бог" meets "Noragami Aragoto" via the shared
/// "noragami" alt title). Every franchise also gets a chronological FranchiseOrder (1, 2, 3...)
/// so the grid can show seasons in watch order.
/// </summary>
public sealed partial class FranchiseService : IFranchiseService
{
    /// <summary>Season/part suffixes one pass of <see cref="SeasonSuffixRegex"/> peels off.</summary>
    [GeneratedRegex(@"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|tv\s*\d+|ova|movie|фильм|сезон\s+\d+|[IVXLCDM]+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SeasonSuffixRegex();

    /// <summary>"Season 1", "2nd Season", "Сезон 3" — the numbers the chronology falls back on.</summary>
    [GeneratedRegex(@"(?:season\s+|\d+(?:st|nd|rd|th)\s+season\s+|сезон\s+)(\d+)$|(\d+)(?:st|nd|rd|th)\s+season$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SeasonNumberRegex();

    /// <summary>Relation types whose two ends provably belong to one franchise.</summary>
    private static readonly HashSet<string> FranchiseRelationTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "PREQUEL", "SEQUEL", "PARENT", "SIDE_STORY", "ALTERNATIVE", "ADAPTATION", "SUMMARY",
    };

    /// <summary>
    /// Base roots this short are unreliable evidence on their own ("K", "Nana"): they count only
    /// when the author or studio matches strictly, per the false-positive guard.
    /// </summary>
    private const int ShortBaseTitleLength = 4;

    /// <summary>
    /// Display-name variant of <see cref="ExtractBaseTitle"/>: "Naruto: Shippuden" → "Naruto".
    /// Kept for callers that want a human-readable franchise name candidate.
    /// </summary>
    public string? InferFranchiseName(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;

        var clean = title.Trim();
        var colonIdx = clean.IndexOfAny([':', '-', '/']);
        if (colonIdx > 2)
        {
            var prefix = clean[..colonIdx].Trim();
            if (prefix.Length >= 3)
            {
                return prefix;
            }
        }

        var match = SeasonSuffixRegex().Replace(clean, "").Trim();
        if (match.Length >= 3 && match != clean)
        {
            return match;
        }

        return null;
    }

    /// <summary>
    /// Strips season suffixes ("2nd Season", "Season 3", "II") and subtitles after a separator,
    /// then normalizes to lowercase letters and digits: the comparison key for franchise roots.
    /// </summary>
    public string? ExtractBaseTitle(string? title) => ComputeBaseTitle(title);

    private static string? ComputeBaseTitle(string? title)
    {
        var clean = CleanBaseTitle(title);
        if (clean is null) return null;
        var normalized = NormalizeTitle(clean);
        return normalized.Length == 0 ? null : normalized;
    }

    /// <summary>
    /// Same stripping as <see cref="ExtractBaseTitle"/> but keeps the original casing and spaces,
    /// so the result can serve as a display name ("Noragami: Aragoto" → "Noragami").
    /// </summary>
    private static string? CleanBaseTitle(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return null;

        var clean = title.Trim();

        // Peel stacked suffixes ("... 2nd Season Part 2") one layer at a time. A strip that leaves
        // less than three characters was a false hit on a roman-numeral lookalike word ("Mix"),
        // so the original title wins back.
        for (var i = 0; i < 3; i++)
        {
            var stripped = SeasonSuffixRegex().Replace(clean, "").Trim();
            if (stripped == clean || stripped.Length < 3) break;
            clean = stripped;
        }

        // Subtitle cut: "Noragami: Aragoto" → "Noragami". Only split when what remains before the
        // separator is a real title, not a one-letter prefix like the "Re" of "Re:Zero".
        var sepIdx = clean.IndexOfAny([':', '-', '/']);
        if (sepIdx > 2)
        {
            clean = clean[..sepIdx].Trim();
        }

        return clean.Length >= 3 ? clean : title.Trim();
    }

    /// <summary>
    /// Lowercase, letters and digits only — the Unicode-aware comparison key, shared with the
    /// duplicate-check flow so both features ask the same question about two titles.
    /// </summary>
    public static string NormalizeKey(string? value) => NormalizeTitle(value);

    /// <summary>Lowercase, letters and digits only — the Unicode-aware comparison key.</summary>
    private static string NormalizeTitle(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;

        var sb = new StringBuilder(value.Length);
        foreach (var ch in value.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(ch))
            {
                sb.Append(ch);
            }
        }

        return sb.ToString();
    }

    /// <summary>
    /// Every name variant worth comparing: display title, romaji, original and the collected alt
    /// titles. This is the cross-language bridge — a Russian Shikimori title carries "Noragami" in
    /// its alt list, so it meets an English AniList sequel there.
    /// </summary>
    private static List<string> GetAllNames(MediaItem item)
    {
        var names = new List<string> { item.Title };

        var romaji = item switch
        {
            Manga m => m.RomajiTitle,
            Movie mv => mv.RomajiTitle,
            TvShow tv => tv.RomajiTitle,
            _ => null,
        };
        if (!string.IsNullOrWhiteSpace(romaji)) names.Add(romaji);
        if (!string.IsNullOrWhiteSpace(item.OriginalTitle)) names.Add(item.OriginalTitle);
        names.AddRange(MediaMetadataApplier.DeserializeAltTitles(item.AltTitles));

        return names
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .Select(n => n.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static (string? Author, string? Studio) GetCreators(MediaItem item) => item switch
    {
        Manga m => (m.Author, null),
        Book b => (b.Author, null),
        VideoGame g => (null, g.Studio),
        Movie mv => (mv.Director, mv.Studio),
        TvShow tv => (null, tv.Studio),
        _ => (null, null),
    };

    private static bool SameCreator(string? a, string? b) =>
        !string.IsNullOrWhiteSpace(a)
        && !string.IsNullOrWhiteSpace(b)
        && string.Equals(a.Trim(), b.Trim(), StringComparison.OrdinalIgnoreCase);

    /// <summary>Per-item cache of everything the matcher needs, so clustering stays O(n²) in cheap set lookups.</summary>
    private sealed class TitleFacts
    {
        public required MediaItem Item { get; init; }

        public required List<string> Names { get; init; }

        /// <summary>Normalized full names — what a relation title is checked against.</summary>
        public required HashSet<string> NameSet { get; init; }

        /// <summary>Normalized base roots — the Level 3 comparison keys.</summary>
        public required List<string> Roots { get; init; }

        public required IReadOnlyList<ExternalRelationDto> Relations { get; init; }
    }

    private static TitleFacts BuildFacts(MediaItem item)
    {
        var names = GetAllNames(item);
        return new TitleFacts
        {
            Item = item,
            Names = names,
            NameSet = names.Select(name => NormalizeTitle(name)).Where(n => n.Length > 0).ToHashSet(StringComparer.Ordinal),
            Roots = names
                .Select(name => ComputeBaseTitle(name))
                .Where(r => r is not null)
                .Select(r => r!)
                .Distinct(StringComparer.Ordinal)
                .ToList(),
            Relations = MediaJsonCache.Deserialize<ExternalRelationDto>(item.RelatedMediaJson),
        };
    }

    // ------------------------------------------------------------------
    // Level 1: the related-media graph. A stored PREQUEL/SEQUEL/ADAPTATION link that points at the
    // other title is definitive — no fuzzy matching runs after it returns true.
    // ------------------------------------------------------------------

    private static bool AreFranchiseRelated(TitleFacts a, TitleFacts b)
    {
        if (a.Item.Id == b.Item.Id) return true;
        if (RelationGraphLinks(a, b) || RelationGraphLinks(b, a)) return true;
        return BaseRootsIntersect(a, b);
    }

    private static bool RelationGraphLinks(TitleFacts source, TitleFacts target)
    {
        foreach (var relation in source.Relations)
        {
            if (relation.Media is null) continue;
            if (!FranchiseRelationTypes.Contains(relation.RelationType ?? string.Empty)) continue;
            if (RelationTargets(relation, source, target)) return true;
        }

        return false;
    }

    /// <summary>True when the relation's external id (same provider) or any of its title variants hits the target.</summary>
    private static bool RelationTargets(ExternalRelationDto relation, TitleFacts source, TitleFacts target)
    {
        var media = relation.Media!;

        // External id match, trusted only when both sides came from the same provider.
        if (!string.IsNullOrWhiteSpace(media.ExternalId) && !string.IsNullOrWhiteSpace(target.Item.ExternalId))
        {
            var provider = string.IsNullOrWhiteSpace(media.ExternalSource) ? source.Item.ExternalSource : media.ExternalSource;
            if (string.Equals(provider, target.Item.ExternalSource, StringComparison.OrdinalIgnoreCase)
                && string.Equals(media.ExternalId, target.Item.ExternalId, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        // Title match against every variant the target carries.
        foreach (var name in new[] { media.Title, media.RomajiTitle, media.OriginalTitle })
        {
            var normalized = NormalizeTitle(name);
            if (normalized.Length > 0 && target.NameSet.Contains(normalized)) return true;
        }

        return false;
    }

    /// <summary>True when the source's graph links the target through a specific franchise relation type.</summary>
    private static bool GraphHasRelation(TitleFacts source, TitleFacts target, string relationType)
    {
        foreach (var relation in source.Relations)
        {
            if (relation.Media is null) continue;
            if (!string.Equals(relation.RelationType, relationType, StringComparison.OrdinalIgnoreCase)) continue;
            if (RelationTargets(relation, source, target)) return true;
        }

        return false;
    }

    // ------------------------------------------------------------------
    // Levels 2+3: base roots. Each name variant is stripped down to its base title
    // ("Noragami Aragoto 2nd Season" → "noragamiaragoto"; the alt title "Noragami" → "noragami");
    // any shared root across the two titles' variant lists makes them one franchise.
    // ------------------------------------------------------------------

    private static bool BaseRootsIntersect(TitleFacts a, TitleFacts b)
    {
        foreach (var root in a.Roots)
        {
            if (!b.Roots.Contains(root)) continue;
            // Ultra-short roots ("K", "Nana") are only allowed with strict author/studio agreement.
            if (root.Length <= ShortBaseTitleLength && !SameCreatorFamily(a.Item, b.Item)) continue;
            return true;
        }

        // Prefix bridge: a sequel rarely repeats the base title verbatim ("Noragami Aragoto" keeps
        // "noragami" only as its prefix), so a long-enough shared prefix is franchise evidence too.
        // Checked both ways — the shorter root may sit on either side.
        foreach (var rootA in a.Roots)
            foreach (var rootB in b.Roots)
            {
                if (rootA.Length > ShortBaseTitleLength
                    && rootA.Length < rootB.Length
                    && rootB.StartsWith(rootA, StringComparison.Ordinal))
                {
                    return true;
                }

                if (rootB.Length > ShortBaseTitleLength
                    && rootB.Length < rootA.Length
                    && rootA.StartsWith(rootB, StringComparison.Ordinal))
                {
                    return true;
                }
            }

        return false;
    }

    private static bool SameCreatorFamily(MediaItem a, MediaItem b)
    {
        var (aAuthor, aStudio) = GetCreators(a);
        var (bAuthor, bStudio) = GetCreators(b);
        return SameCreator(aAuthor, bAuthor) || SameCreator(aStudio, bStudio);
    }

    /// <summary>
    /// Groups related titles into clusters (union-find over the pairwise matcher), so one shared
    /// root chains a whole franchise together instead of requiring every pair to match directly.
    /// </summary>
    private static List<List<TitleFacts>> BuildClusters(List<TitleFacts> facts)
    {
        var parent = Enumerable.Range(0, facts.Count).ToArray();

        int Find(int i)
        {
            while (parent[i] != i)
            {
                parent[i] = parent[parent[i]];
                i = parent[i];
            }

            return i;
        }

        for (var i = 0; i < facts.Count; i++)
        {
            for (var j = i + 1; j < facts.Count; j++)
            {
                if (AreFranchiseRelated(facts[i], facts[j]))
                {
                    parent[Find(i)] = Find(j);
                }
            }
        }

        var clusters = new Dictionary<int, List<TitleFacts>>();
        for (var i = 0; i < facts.Count; i++)
        {
            var root = Find(i);
            if (!clusters.TryGetValue(root, out var members))
            {
                clusters[root] = members = [];
            }

            members.Add(facts[i]);
        }

        return clusters.Values.ToList();
    }

    /// <summary>
    /// Picks the franchise display name: the shortest clean base among every variant of every
    /// member, which is how "Noragami" beats "Noragami Aragoto 2nd Season".
    /// </summary>
    private static string? ChooseClusterName(List<TitleFacts> cluster)
    {
        string? best = null;
        var bestLength = int.MaxValue;

        foreach (var fact in cluster)
        {
            foreach (var name in fact.Names)
            {
                var clean = CleanBaseTitle(name);
                if (clean is null) continue;
                var root = NormalizeTitle(clean);
                if (root.Length <= ShortBaseTitleLength) continue;
                if (root.Length < bestLength)
                {
                    bestLength = root.Length;
                    best = clean;
                }
            }
        }

        return best;
    }

    // ------------------------------------------------------------------
    // Chronological order: prequel→sequel edges first, then release date, then the season number
    // in the title, then the date the title entered the library.
    // ------------------------------------------------------------------

    private static void AssignChronologicalOrder(List<TitleFacts> members)
    {
        var ordered = members
            .OrderBy(f => f, Comparer<TitleFacts>.Create((a, b) => CompareChronology(a!, b!)))
            .ToList();
        for (var i = 0; i < ordered.Count; i++)
        {
            ordered[i].Item.FranchiseOrder = i + 1;
        }
    }

    private static int CompareChronology(TitleFacts? a, TitleFacts? b)
    {
        if (ReferenceEquals(a, b)) return 0;
        if (a is null) return -1;
        if (b is null) return 1;

        // 1. Explicit graph knowledge: a prequel sorts before its sequel.
        if (IsSequelOf(a, b)) return -1;
        if (IsSequelOf(b, a)) return 1;

        // 2. Release date (or bare year) — the natural watch order.
        var byDate = CompareRelease(a.Item, b.Item);
        if (byDate != 0) return byDate;

        // 3. "Season 1" before "Season 2".
        var bySeason = ExtractSeasonNumber(a.Item.Title).CompareTo(ExtractSeasonNumber(b.Item.Title));
        if (bySeason != 0) return bySeason;

        // 4. Library creation date as the last resort.
        return a.Item.CreatedAt.CompareTo(b.Item.CreatedAt);
    }

    /// <summary>The sequel declares its prequel, or the prequel declares its sequel — either edge orders the pair.</summary>
    private static bool IsSequelOf(TitleFacts earlier, TitleFacts later) =>
        GraphHasRelation(later, earlier, "PREQUEL")
        || GraphHasRelation(earlier, later, "SEQUEL");

    private static int CompareRelease(MediaItem a, MediaItem b)
    {
        if (a.ReleaseDate is { } aDate && b.ReleaseDate is { } bDate)
        {
            return aDate.CompareTo(bDate);
        }

        var aYear = a.ReleaseYear ?? a.ReleaseDate?.Year;
        var bYear = b.ReleaseYear ?? b.ReleaseDate?.Year;
        if (aYear is { } ay && bYear is { } by)
        {
            return ay.CompareTo(by);
        }

        // Titles with no date at all sink below dated ones but stay together.
        return (aYear is null, bYear is null) switch
        {
            (true, true) => 0,
            (true, false) => 1,
            (false, true) => -1,
            _ => 0,
        };
    }

    private static int ExtractSeasonNumber(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return 0;
        var match = SeasonNumberRegex().Match(title);
        if (!match.Success) return 0;
        var group = match.Groups[1].Success ? match.Groups[1] : match.Groups[2];
        return int.TryParse(group.Value, out var number) ? number : 0;
    }

    // ------------------------------------------------------------------
    // Public flows
    // ------------------------------------------------------------------

    /// <summary>
    /// Full library rescan: clusters every title with its relatives, joins each cluster to an
    /// existing franchise when one of its members already had one (merging split franchises),
    /// names the new ones, and renumbers FranchiseOrder inside every touched franchise.
    /// Returns how many rows were written.
    /// </summary>
    public async Task<int> AutoBackfillFranchisesAsync(AppDbContext db, CancellationToken ct = default)
    {
        var conn = db.Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var items = (await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct)).ToList();
        var before = items.ToDictionary(m => m.Id, m => (m.FranchiseId, m.FranchiseOrder));
        var facts = items.Select(BuildFacts).ToList();

        var knownFranchises = await db.GetAllFranchisesAsync(ct);
        var franchisesByName = new Dictionary<string, Franchise>(StringComparer.Ordinal);
        foreach (var franchise in knownFranchises)
        {
            franchisesByName.TryAdd(NormalizeTitle(franchise.Name), franchise);
        }

        var touched = new HashSet<Guid>();
        var redundant = new HashSet<Guid>();

        var clusters = BuildClusters(facts);

        foreach (var cluster in clusters)
        {
            // A lone title with no relatives and no franchise is not evidence of a franchise.
            if (cluster.Count <= 1 && cluster[0].Item.FranchiseId is null) continue;

            // Join an existing franchise when any member already has one; the most-referenced id
            // wins so a merged cluster converges on one row instead of flip-flopping between scans.
            var targetId = cluster
                .Select(f => f.Item.FranchiseId)
                .Where(id => id is not null)
                .GroupBy(id => id!.Value)
                .OrderByDescending(g => g.Count())
                .Select(g => (Guid?)g.Key)
                .FirstOrDefault();

            var franchise = targetId is { } id ? knownFranchises.FirstOrDefault(f => f.Id == id) : null;

            if (franchise is null)
            {
                var name = ChooseClusterName(cluster);
                if (string.IsNullOrWhiteSpace(name)) continue;

                if (!franchisesByName.TryGetValue(NormalizeTitle(name), out franchise))
                {
                    franchise = new Franchise { Id = Guid.NewGuid(), Name = name };
                    franchisesByName[NormalizeTitle(name)] = franchise;
                    knownFranchises.Add(franchise);
                    await db.CreateFranchiseAsync(franchise, ct);
                }
            }

            foreach (var member in cluster)
            {
                if (member.Item.FranchiseId is { } current && current != franchise.Id)
                {
                    redundant.Add(current);
                }

                member.Item.FranchiseId = franchise.Id;
            }

            touched.Add(franchise.Id);
        }

        // Renumber every franchise the scan touched (its full membership, not just cluster members).
        foreach (var franchiseId in touched)
        {
            var members = facts.Where(f => f.Item.FranchiseId == franchiseId).ToList();
            if (members.Count == 0) continue;
            if (members.Count == 1)
            {
                members[0].Item.FranchiseOrder ??= 1;
            }
            else
            {
                AssignChronologicalOrder(members);
            }
        }

        // A franchise row only survives if something outside the merged clusters still points at it.
        foreach (var orphanId in redundant)
        {
            if (items.Any(m => m.FranchiseId == orphanId))
            {
                continue;
            }

            touched.Remove(orphanId);
            await conn.ExecuteAsync("DELETE FROM Franchises WHERE Id = @id;", new { id = orphanId.ToString().ToUpperInvariant() });
        }

        var updated = 0;
        foreach (var item in items)
        {
            var (prevId, prevOrder) = before[item.Id];
            if (!NullableGuidEquals(prevId, item.FranchiseId) || !NullableIntEquals(prevOrder, item.FranchiseOrder))
            {
                await db.UpdateMediaItemAsync(item, ct);
                updated++;
            }
        }

        return updated;
    }

    private static bool NullableGuidEquals(Guid? a, Guid? b) => Nullable.Equals(a, b);

    private static bool NullableIntEquals(int? a, int? b) => Nullable.Equals(a, b);

    /// <summary>
    /// Create-time hook: an explicitly requested franchise name keeps its literal meaning; without
    /// one the new title is matched against every existing row and joins its relatives' franchise
    /// immediately, with the whole franchise renumbered.
    /// </summary>
    public async Task LinkFranchiseOnCreateAsync(AppDbContext db, MediaItem item, string? requestedFranchiseName, CancellationToken ct = default)
    {
        if (item.FranchiseId is not null) return;

        var conn = db.Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        Franchise? franchise = null;
        List<TitleFacts>? relatives = null;
        var itemFacts = BuildFacts(item);

        if (!string.IsNullOrWhiteSpace(requestedFranchiseName))
        {
            var trimmed = requestedFranchiseName.Trim();
            franchise = await db.GetFranchiseByNameAsync(trimmed, ct);
            if (franchise is null)
            {
                franchise = new Franchise { Id = Guid.NewGuid(), Name = trimmed };
                await db.CreateFranchiseAsync(franchise, ct);
            }
        }
        else
        {
            var knownFranchises = await db.GetAllFranchisesAsync(ct);
            var library = (await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct))
                .Where(m => m.Id != item.Id)
                .ToList();

            // Level 0 shortcut: the title's base root is an existing franchise's own name.
            franchise = knownFranchises.FirstOrDefault(f =>
                itemFacts.Roots.Any(r => r.Length > ShortBaseTitleLength && r == NormalizeTitle(f.Name)));

            if (franchise is null)
            {
                foreach (var other in library.Select(BuildFacts))
                {
                    if (!AreFranchiseRelated(itemFacts, other)) continue;

                    if (other.Item.FranchiseId is { } relativeId)
                    {
                        franchise = knownFranchises.FirstOrDefault(f => f.Id == relativeId);
                    }
                    else
                    {
                        franchise = new Franchise
                        {
                            Id = Guid.NewGuid(),
                            Name = ChooseClusterName([itemFacts, other]) ?? item.Title,
                        };
                        await db.CreateFranchiseAsync(franchise, ct);
                        relatives = [other];
                    }

                    break;
                }
            }
        }

        if (franchise is null) return;

        item.FranchiseId = franchise.Id;
        item.Franchise = franchise;

        // Pull the relatives in and renumber the whole franchise chronologically before writing
        // them, so each persisted row carries its final FranchiseOrder. The incoming item itself
        // is persisted by the caller (CreateMediaHandler), so only existing rows are written here.
        var members = (await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct))
            .Where(m => m.Id != item.Id && m.FranchiseId == franchise.Id)
            .Select(BuildFacts)
            .ToList();

        foreach (var other in relatives ?? [])
        {
            other.Item.FranchiseId = franchise.Id;
            members.Add(other);
        }

        members.Add(itemFacts);
        // An explicit FranchiseOrder from the create request is the user's word — the automatic
        // chronology only fills the gap when no order was asked for.
        if (item.FranchiseOrder is null)
        {
            AssignChronologicalOrder(members);
        }

        foreach (var other in relatives ?? [])
        {
            await db.UpdateMediaItemAsync(other.Item, ct);
        }
    }

    public async Task LinkFranchiseOnUpdateAsync(AppDbContext db, MediaItem item, Guid? requestedFranchiseId, string? requestedFranchiseName, CancellationToken ct = default)
    {
        if (requestedFranchiseId is not null)
        {
            item.FranchiseId = requestedFranchiseId;
            return;
        }

        if (string.IsNullOrWhiteSpace(requestedFranchiseName))
        {
            return;
        }

        var trimmedName = requestedFranchiseName.Trim();
        var franchise = await db.GetFranchiseByNameAsync(trimmedName, ct);

        if (franchise is null)
        {
            franchise = new Franchise { Id = Guid.NewGuid(), Name = trimmedName };
            await db.CreateFranchiseAsync(franchise, ct);
        }

        item.FranchiseId = franchise.Id;
        item.Franchise = franchise;
    }

    /// <summary>
    /// Binds games that RAWG's <c>/game-series</c> put on one row into a single franchise: every
    /// library game whose RAWG id or normalized title appears in the series joins the same
    /// <c>FranchiseId</c>, and <c>FranchiseOrder</c> is renumbered chronologically (release year
    /// first, via the same <see cref="AssignChronologicalOrder"/> the scans use). An explicit user
    /// binding always wins — a row that already has a franchise is left alone, and if no other
    /// member carries the series, two lone titles never make a franchise.
    /// Returns how many rows were written.
    /// </summary>
    public async Task<int> LinkGameSeriesAsync(
        AppDbContext db,
        MediaItem item,
        IReadOnlyList<ExternalRelationDto> series,
        CancellationToken ct = default)
    {
        if (item is not VideoGame || item.FranchiseId is not null || series.Count == 0)
        {
            return 0;
        }

        var conn = db.Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var seriesIds = series
            .Select(s => s.Media?.ExternalId?.Trim())
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var seriesNames = series
            .Select(s => NormalizeKey(s.Media?.Title))
            .Where(n => n.Length > 0)
            .ToHashSet(StringComparer.Ordinal);

        var library = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
        var members = library
            .Where(game => game is VideoGame)
            .Where(game =>
                (string.Equals(game.ExternalSource, "rawg", StringComparison.OrdinalIgnoreCase)
                    && game.ExternalId is not null && seriesIds.Contains(game.ExternalId))
                || seriesNames.Contains(NormalizeKey(game.Title)))
            .ToList();

        // One hit is just the game itself: a single title is not evidence of a franchise.
        if (members.Count < 2)
        {
            return 0;
        }

        // Join the franchise one of the members already belongs to; otherwise name it after the
        // shortest title in the group — the base game ("The Witcher"), not its longest sequel.
        var franchiseId = members
            .Select(m => m.FranchiseId)
            .FirstOrDefault(id => id is not null);
        if (franchiseId is null)
        {
            var name = members
                .Select(m => m.Title.Trim())
                .OrderBy(t => t.Length)
                .First();
            var franchise = new Franchise { Id = Guid.NewGuid(), Name = name };
            await db.CreateFranchiseAsync(franchise, ct);
            franchiseId = franchise.Id;
        }

        var facts = members.Select(BuildFacts).ToList();
        var before = facts.ToDictionary(f => f.Item.Id, f => (f.Item.FranchiseId, f.Item.FranchiseOrder));

        foreach (var fact in facts)
        {
            fact.Item.FranchiseId = franchiseId;
        }

        AssignChronologicalOrder(facts);
        var changed = 0;
        foreach (var fact in facts)
        {
            var (prevId, prevOrder) = before[fact.Item.Id];
            if (NullableGuidEquals(prevId, fact.Item.FranchiseId)
                && NullableIntEquals(prevOrder, fact.Item.FranchiseOrder))
            {
                continue;
            }

            fact.Item.MarkUpdated();
            await db.UpdateMediaItemAsync(fact.Item, ct);
            changed++;
        }

        MediaListCache.Invalidate();
        return changed;
    }
}
