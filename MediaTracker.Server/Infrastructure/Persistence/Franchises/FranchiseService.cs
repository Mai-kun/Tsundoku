using System.Text.RegularExpressions;
using Dapper;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Domain.Entities;
using Microsoft.Data.Sqlite;

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
    [GeneratedRegex(@"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|[IVXLCDM]+)$", RegexOptions.IgnoreCase)]
    private static partial Regex SeasonSuffixRegex();

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

    public async Task AutoBackfillFranchisesAsync(AppDbContext db, CancellationToken ct = default)
    {
        var conn = db.Connection;
        if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var unlinked = await db.LoadMediaItemsAsync(null, null, null, null, null, null, ct);
        unlinked = unlinked.Where(m => m.FranchiseId == null).ToList();
        if (unlinked.Count == 0) return;

        // Load the whole franchise table once
        var knownFranchises = (await db.GetAllFranchisesAsync(ct))
            .ToDictionary(f => f.Name.ToLower(), StringComparer.Ordinal);

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
                await db.CreateFranchiseAsync(franchise, ct);
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

        // Persist all updated items
        foreach (var item in unlinked.Where(m => m.FranchiseId.HasValue))
        {
            await db.UpdateMediaItemAsync(item, ct);
        }
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
        var franchise = await db.GetFranchiseByNameAsync(franchiseName, ct);

        if (franchise is not null)
        {
            item.FranchiseId = franchise.Id;
            item.Franchise = franchise;
            return;
        }

        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var siblingExists = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM MediaItems WHERE LOWER(Title) = @name OR FranchiseId IN (SELECT Id FROM Franchises WHERE LOWER(Name) = @name);",
            new { name = lowerFranchiseName, id = Guid.Empty.ToString().ToUpperInvariant() }) > 0;

        if (siblingExists || !string.IsNullOrWhiteSpace(requestedFranchiseName))
        {
            franchise = new Franchise { Id = Guid.NewGuid(), Name = franchiseName };
            await db.CreateFranchiseAsync(franchise, ct);
            item.FranchiseId = franchise.Id;
            item.Franchise = franchise;

            var siblingItem = await conn.QueryFirstOrDefaultAsync<MediaItemRow>(
                "SELECT * FROM MediaItems WHERE FranchiseId IS NULL AND LOWER(Title) = @name;",
                new { name = lowerFranchiseName });
            if (siblingItem is not null)
            {
                siblingItem.FranchiseId = franchise.Id.ToString().ToUpperInvariant();
                await db.UpdateMediaItemAsync(siblingItem.ToEntity(), ct);
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
        var franchise = await db.GetFranchiseByNameAsync(trimmedName, ct);

        if (franchise is null)
        {
            franchise = new Franchise { Id = Guid.NewGuid(), Name = trimmedName };
            await db.CreateFranchiseAsync(franchise, ct);
        }

        item.FranchiseId = franchise.Id;
        item.Franchise = franchise;
    }
}
