using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;

namespace MediaTracker.Server.Features.Media.FindDuplicates;

/// <summary>
/// The title being added: <see cref="Title"/> plus every variant the search result carried
/// (romaji, original, provider synonyms) — the cross-language bridge that lets Shikimori's
/// «Бездомный бог» recognize AniList's "Noragami" through the synonym list.
/// </summary>
public sealed record FindDuplicatesQuery(
    string Title,
    string? ExternalSource,
    string? ExternalId,
    string? RomajiTitle,
    string? OriginalTitle,
    IReadOnlyList<string>? Synonyms,
    int? ReleaseYear);

/// <summary>One library row that looks like the title being added.</summary>
public sealed record DuplicateCandidateDto(
    Guid Id,
    string Title,
    string Type,
    bool IsAnime,
    string? ExternalSource,
    string? ExternalId,
    int? ReleaseYear,
    string? CoverUrl,
    string MatchReason);

public interface IFindDuplicatesHandler
{
    Task<IReadOnlyList<DuplicateCandidateDto>> HandleAsync(FindDuplicatesQuery query, CancellationToken ct = default);
}

/// <summary>
/// Answers "is this title already in the library?" before a new row is created: the same title
/// arrives under different names from different providers (Shikimori's "Бездомный бог" is
/// AniList's "Noragami"), so the check compares every name variant and the stripped base title,
/// mirroring the franchise matcher minus the prefix bridge — a sequel must NOT read as a duplicate.
/// </summary>
public sealed class FindDuplicatesHandler(AppDbContext db, IFranchiseService franchiseService) : IFindDuplicatesHandler
{
    public async Task<IReadOnlyList<DuplicateCandidateDto>> HandleAsync(FindDuplicatesQuery query, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(query.Title))
        {
            return [];
        }

        var queryNames = new List<string>();
        foreach (var name in new[] { query.Title, query.RomajiTitle, query.OriginalTitle })
        {
            if (!string.IsNullOrWhiteSpace(name)) queryNames.Add(name.Trim());
        }
        if (query.Synonyms is { Count: > 0 })
        {
            queryNames.AddRange(query.Synonyms.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.Trim()));
        }
        var queryNameSet = queryNames
            .Select(FranchiseService.NormalizeKey)
            .Where(n => n.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
        var queryRoots = queryNames
            .Select(name => franchiseService.ExtractBaseTitle(name))
            .Where(r => r is { Length: > 4 })
            .Select(r => r!)
            .ToHashSet(StringComparer.Ordinal);

        var items = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
        var candidates = new List<DuplicateCandidateDto>();

        foreach (var item in items)
        {
            var reason = MatchReason(item, query, queryNameSet, queryRoots);
            if (reason is null) continue;

            candidates.Add(new DuplicateCandidateDto(
                item.Id,
                item.Title,
                MediaResponseMapper.GetType(item),
                item is TvShow { IsAnime: true } or Movie { IsAnime: true },
                item.ExternalSource,
                item.ExternalId,
                item.ReleaseYear,
                item.CoverUrl,
                reason));
        }

        return candidates;
    }

    private string? MatchReason(
        MediaItem item,
        FindDuplicatesQuery query,
        HashSet<string> queryNameSet,
        HashSet<string> queryRoots)
    {
        // Same provider record — the definition of a duplicate.
        if (!string.IsNullOrWhiteSpace(item.ExternalId)
            && !string.IsNullOrWhiteSpace(item.ExternalSource)
            && !string.IsNullOrWhiteSpace(query.ExternalId)
            && !string.IsNullOrWhiteSpace(query.ExternalSource)
            && string.Equals(item.ExternalId.Trim(), query.ExternalId.Trim(), StringComparison.OrdinalIgnoreCase)
            && string.Equals(item.ExternalSource.Trim(), query.ExternalSource.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            return "same_source_record";
        }

        var romaji = item switch
        {
            Manga m => m.RomajiTitle,
            Movie mv => mv.RomajiTitle,
            TvShow tv => tv.RomajiTitle,
            _ => null,
        };
        var itemNames = new List<string>();
        foreach (var name in new[] { item.Title, romaji, item.OriginalTitle })
        {
            if (!string.IsNullOrWhiteSpace(name)) itemNames.Add(name.Trim());
        }
        itemNames.AddRange(MediaMetadataApplier.DeserializeAltTitles(item.AltTitles));
        var itemNameSet = itemNames
            .Select(FranchiseService.NormalizeKey)
            .Where(n => n.Length > 0)
            .ToHashSet(StringComparer.Ordinal);

        // Full-name hit in any language: "Бездомный бог" is stored as an alt title of the AniList row.
        if (itemNameSet.Overlaps(queryNameSet))
        {
            return "exact_name";
        }

        // Same stripped base ("Noragami: Stray God" roots to "noragami"). Deliberately no prefix
        // bridge: "Noragami" and "Noragami Aragoto" are different titles, not duplicates. A base
        // hit with a different release year is a sequel season, not the same record, so the years
        // must agree (or one side must be unknown) before it counts.
        var itemRoots = itemNames
            .Select(name => franchiseService.ExtractBaseTitle(name))
            .Where(r => r is { Length: > 4 })
            .Select(r => r!);
        if (itemRoots.Any(queryRoots.Contains) && YearsCompatible(item.ReleaseYear, query.ReleaseYear))
        {
            return "base_title";
        }

        return null;
    }

    /// <summary>A sequel is usually the next year, so base-root hits need the SAME year when
    /// both sides know one; a missing year keeps the check permissive.</summary>
    private static bool YearsCompatible(int? itemYear, int? queryYear) =>
        itemYear is null || queryYear is null || itemYear.Value == queryYear.Value;
}
