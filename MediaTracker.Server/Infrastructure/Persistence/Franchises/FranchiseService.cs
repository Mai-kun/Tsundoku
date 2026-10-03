using System.Text.RegularExpressions;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Infrastructure.Persistence.Franchises;

public interface IFranchiseService
{
    string? InferFranchiseName(string? title);
    Task AutoBackfillFranchisesAsync(AppDbContext db, CancellationToken ct = default);
    Task LinkFranchiseOnCreateAsync(AppDbContext db, MediaItem item, string? requestedFranchiseName, CancellationToken ct = default);
    Task LinkFranchiseOnUpdateAsync(AppDbContext db, MediaItem item, Guid? requestedFranchiseId, string? requestedFranchiseName, CancellationToken ct = default);
}

public sealed partial class FranchiseService : IFranchiseService
{
    private static readonly Regex SeasonSuffixRegex = new(
        @"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|[IVXLCDM]+)$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

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

        var match = SeasonSuffixRegex.Replace(clean, "").Trim();
        if (match.Length >= 3 && match != clean)
        {
            return match;
        }

        return null;
    }

    public async Task AutoBackfillFranchisesAsync(AppDbContext db, CancellationToken ct = default)
    {
        var unlinked = await db.MediaItems.Where(m => m.FranchiseId == null).ToListAsync(ct);
        if (unlinked.Count == 0) return;

        // Load the whole franchise table once: the loop below runs per inferred name, and a
        // FirstOrDefaultAsync per group turned startup backfill into an N+1 query storm.
        var knownFranchises = await db.Franchises.ToDictionaryAsync(f => f.Name.ToLower(), StringComparer.Ordinal, ct);

        var groups = unlinked
            .Select(m => new { Item = m, FranchiseName = InferFranchiseName(m.Title) })
            .Where(x => !string.IsNullOrWhiteSpace(x.FranchiseName))
            .GroupBy(x => x.FranchiseName!.ToLowerInvariant())
            .ToList();

        foreach (var grp in groups)
        {
            var inferredName = grp.First().FranchiseName!;
            var exactMatchItem = unlinked.FirstOrDefault(m => m.Title.Equals(inferredName, StringComparison.OrdinalIgnoreCase));

            // A lone title with no sibling sharing the prefix is not evidence of a franchise.
            if (grp.Count() <= 1 && exactMatchItem is null)
            {
                continue;
            }

            if (!knownFranchises.TryGetValue(grp.Key, out var franchise))
            {
                franchise = new Franchise { Id = Guid.NewGuid(), Name = inferredName };
                knownFranchises[grp.Key] = franchise;
                db.Franchises.Add(franchise);
            }

            foreach (var x in grp)
            {
                x.Item.FranchiseId = franchise.Id;
            }

            if (exactMatchItem is not null && exactMatchItem.FranchiseId is null)
            {
                exactMatchItem.FranchiseId = franchise.Id;
            }
        }

        await db.SaveChangesAsync(ct);
    }

    public async Task LinkFranchiseOnCreateAsync(AppDbContext db, MediaItem item, string? requestedFranchiseName, CancellationToken ct = default)
    {
        var franchiseName = !string.IsNullOrWhiteSpace(requestedFranchiseName)
            ? requestedFranchiseName.Trim()
            : InferFranchiseName(item.Title);

        if (item.FranchiseId is not null || string.IsNullOrWhiteSpace(franchiseName))
        {
            return;
        }

        var lowerFranchiseName = franchiseName.ToLower();
        var franchise = await db.Franchises.FirstOrDefaultAsync(f => f.Name.ToLower() == lowerFranchiseName, ct);

        if (franchise is not null)
        {
            item.FranchiseId = franchise.Id;
            item.Franchise = franchise;
            return;
        }

        var siblingExists = await db.MediaItems.AnyAsync(
            m => m.Title.ToLower() == lowerFranchiseName || (m.Franchise != null && m.Franchise.Name.ToLower() == lowerFranchiseName),
            ct);

        if (siblingExists || !string.IsNullOrWhiteSpace(requestedFranchiseName))
        {
            franchise = new Franchise { Id = Guid.NewGuid(), Name = franchiseName };
            db.Franchises.Add(franchise);
            item.FranchiseId = franchise.Id;
            item.Franchise = franchise;

            var siblingItem = await db.MediaItems.FirstOrDefaultAsync(
                m => m.FranchiseId == null && m.Title.ToLower() == lowerFranchiseName,
                ct);

            if (siblingItem is not null)
            {
                siblingItem.FranchiseId = franchise.Id;
            }
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
        var lowerName = trimmedName.ToLower();
        var franchise = await db.Franchises.FirstOrDefaultAsync(f => f.Name.ToLower() == lowerName, ct);

        if (franchise is null)
        {
            franchise = new Franchise { Id = Guid.NewGuid(), Name = trimmedName };
            db.Franchises.Add(franchise);
        }

        item.FranchiseId = franchise.Id;
        item.Franchise = franchise;
    }
}
