using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.FindDuplicates;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using Xunit;

namespace MediaTracker.Tests;

/// <summary>
/// The duplicate guard behind the add flow: the same title from a second provider must be
/// recognised through alt titles and base roots, while a sequel must not read as a duplicate.
/// </summary>
public class FindDuplicatesTests
{
    private static AppDbContext CreateContext()
    {
        var db = new AppDbContext($"Data Source={Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.db")}");
        db.Database.EnsureCreated();
        return db;
    }

    private static FindDuplicatesQuery Query(string title, string? source = null, string? id = null, string[]? synonyms = null, int? year = null) =>
        new(title, source, id, null, null, synonyms, year);

    [Fact]
    public async Task ShouldFindDuplicateByAltTitleAcrossProviders()
    {
        using var db = CreateContext();
        // The AniList anime already added; the Shikimori row carries the Russian name.
        db.MediaItems.Add(new TvShow { Title = "Noragami", IsAnime = true });
        await db.SaveChangesAsync();

        // Shikimori's «Бездомный бог» lists "Noragami" among its alt names.
        var existing = db.MediaItems.Single();
        existing.AltTitles = "[\"Noragami\",\"Stray God\"]";

        var handler = new FindDuplicatesHandler(db, new FranchiseService());
        var hits = await handler.HandleAsync(Query("Бездомный бог", "Shikimori", "999", ["Noragami"]));

        hits.Should().ContainSingle(h => h.Id == existing.Id && h.MatchReason == "exact_name");
    }

    [Fact]
    public async Task ShouldFindDuplicateByBaseTitle()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new Manga { Title = "Noragami: Stray God", ExternalSource = "AniList" });
        await db.SaveChangesAsync();

        var handler = new FindDuplicatesHandler(db, new FranchiseService());
        var hits = await handler.HandleAsync(Query("Noragami", "AniList", "20447"));

        hits.Should().ContainSingle(h => h.MatchReason == "base_title");
    }

    [Fact]
    public async Task ShouldFlagSameProviderRecord()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new TvShow { Title = "Noragami", IsAnime = true, ExternalSource = "AniList", ExternalId = "20447" });
        await db.SaveChangesAsync();

        var handler = new FindDuplicatesHandler(db, new FranchiseService());
        var hits = await handler.HandleAsync(Query("Noragami", "AniList", "20447"));

        hits.Should().ContainSingle(h => h.MatchReason == "same_source_record");
    }

    [Fact]
    public async Task ShouldNotFlagSequelAsDuplicate()
    {
        using var db = CreateContext();
        db.MediaItems.Add(new TvShow { Title = "Noragami", IsAnime = true });
        await db.SaveChangesAsync();

        // The sequel's base root only prefixes the original's — not a duplicate.
        var handler = new FindDuplicatesHandler(db, new FranchiseService());
        var hits = await handler.HandleAsync(Query("Noragami Aragoto", "AniList", "20460"));

        hits.Should().BeEmpty();
    }

    [Fact]
    public async Task ShouldNotFlagNextSeasonWithSameBaseRootAndNewerYear()
    {
        using var db = CreateContext();
        // «Бездомный бог» (2014); the sequel «Бездомный бог: Арагото» strips to the same base.
        db.MediaItems.Add(new TvShow { Title = "Бездомный бог", IsAnime = true, ReleaseYear = 2014 });
        await db.SaveChangesAsync();

        var handler = new FindDuplicatesHandler(db, new FranchiseService());
        var hits = await handler.HandleAsync(Query("Бездомный бог: Арагото", "Shikimori", "20520", null, 2015));

        hits.Should().BeEmpty();
    }
}
