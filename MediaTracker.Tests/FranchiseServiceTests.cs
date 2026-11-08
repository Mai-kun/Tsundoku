using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using Xunit;

namespace MediaTracker.Tests;

public class FranchiseServiceTests
{
    private static AppDbContext CreateContext()
    {
        var db = new AppDbContext($"Data Source={Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.db")}");
        db.Database.EnsureCreated();
        return db;
    }

    private static List<ExternalRelationDto> Relations(string relationType, string targetTitle) =>
    [
        new(relationType, new ExternalMediaDto { ExternalId = "rel-1", Title = targetTitle, Type = "MANGA" }),
    ];

    [Theory]
    [InlineData("Dune: Part One", "Dune")]
    [InlineData("Matrix - Reloaded", "Matrix")]
    [InlineData("Star Wars/New Hope", "Star Wars")]
    [InlineData("Season 2", null)]
    [InlineData("Part 1", null)]
    [InlineData("Abc", null)]
    [InlineData("ABCD: Test", "ABCD")]
    public void InferFranchiseName_ShouldHandlePrefixesAndSuffixes(string title, string? expected)
    {
        var service = new FranchiseService();
        service.InferFranchiseName(title).Should().Be(expected);
    }

    [Theory]
    [InlineData("Noragami Aragoto 2nd Season", "noragamiaragoto")]
    [InlineData("Noragami: Aragoto", "noragami")]
    [InlineData("Клинок, рассекающий демонов: Поезд «Бесконечный»", "клинокрассекающийдемонов")]
    [InlineData("Kimi no Na wa. Movie", "kiminonawa")]
    [InlineData(null, null)]
    public void ExtractBaseTitle_ShouldStripSeasonSuffixesAndSubtitles(string? title, string? expected) =>
        new FranchiseService().ExtractBaseTitle(title).Should().Be(expected);

    [Fact]
    public async Task AutoBackfill_ShouldMergeCrossLanguageSeasonsInChronologicalOrder()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            // Season 1 added from Shikimori, in Russian — but its alt titles carry the romaji root.
            new Manga
            {
                Title = "Бездомный бог",
                AltTitles = MediaMetadataApplier.SerializeAltTitles(["Noragami", "Stray God"]),
                ReleaseDate = new DateTime(2014, 1, 5, 0, 0, 0, DateTimeKind.Utc),
            },
            // Season 2 added from AniList, in English/romaji.
            new Manga
            {
                Title = "Noragami Aragoto",
                RomajiTitle = "Noragami Aragoto",
                ReleaseDate = new DateTime(2015, 10, 5, 0, 0, 0, DateTimeKind.Utc),
            });
        await db.SaveChangesAsync();

        var updated = await new FranchiseService().AutoBackfillFranchisesAsync(db);

        updated.Should().Be(2);
        var franchises = await db.GetAllFranchisesAsync();
        franchises.Should().ContainSingle(f => f.Name == "Noragami");
        var franchise = franchises.Single(f => f.Name == "Noragami");

        var first = db.MediaItems.Single(m => m.Title == "Бездомный бог");
        var second = db.MediaItems.Single(m => m.Title == "Noragami Aragoto");
        first.FranchiseId.Should().Be(franchise.Id);
        second.FranchiseId.Should().Be(franchise.Id);
        first.FranchiseOrder.Should().Be(1);
        second.FranchiseOrder.Should().Be(2);
    }

    [Fact]
    public async Task AutoBackfill_ShouldOrderPartsBySequelGraph()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Manga
            {
                Title = "Alpha Saga",
                RelatedMediaJson = MediaJsonCache.Serialize(Relations("SEQUEL", "Beta Saga")),
            },
            new Manga { Title = "Beta Saga" });
        await db.SaveChangesAsync();

        await new FranchiseService().AutoBackfillFranchisesAsync(db);

        db.MediaItems.Single(m => m.Title == "Alpha Saga").FranchiseOrder.Should().Be(1);
        db.MediaItems.Single(m => m.Title == "Beta Saga").FranchiseOrder.Should().Be(2);

        var franchiseId = db.MediaItems.Single(m => m.Title == "Alpha Saga").FranchiseId;
        franchiseId.Should().NotBeNull();
        db.MediaItems.Single(m => m.Title == "Beta Saga").FranchiseId.Should().Be(franchiseId);
    }

    [Fact]
    public async Task AutoBackfill_ShouldMergeSplitFranchisesIntoOne()
    {
        using var db = CreateContext();
        var splitA = new Franchise { Id = Guid.NewGuid(), Name = "Split A" };
        var splitB = new Franchise { Id = Guid.NewGuid(), Name = "Split B" };
        await db.CreateFranchiseAsync(splitA);
        await db.CreateFranchiseAsync(splitB);

        db.MediaItems.AddRange(
            new Manga { Title = "Long Series: Part 1", FranchiseId = splitA.Id },
            new Manga { Title = "Long Series: Part 2", FranchiseId = splitB.Id });
        await db.SaveChangesAsync();

        await new FranchiseService().AutoBackfillFranchisesAsync(db);

        var items = db.MediaItems.ToList();
        items.Should().OnlyContain(m => m.FranchiseId == items[0].FranchiseId);
        // The merged franchises collapse into a single surviving row.
        (await db.GetAllFranchisesAsync()).Should().ContainSingle();
    }

    [Fact]
    public async Task LinkFranchiseOnCreate_ShouldJoinRelativesFranchise()
    {
        using var db = CreateContext();
        var existing = new Manga
        {
            Title = "Noragami",
            ReleaseDate = new DateTime(2014, 1, 5, 0, 0, 0, DateTimeKind.Utc),
        };
        db.MediaItems.Add(existing);
        await db.SaveChangesAsync();

        var newcomer = new Manga { Title = "Noragami Aragoto", RomajiTitle = "Noragami Aragoto" };
        await new FranchiseService().LinkFranchiseOnCreateAsync(db, newcomer, null);

        // The service mutates the persisted rows, so assert against what the database now holds.
        var rows = (await db.LoadMediaItemsAsync(null, null, null, null, null, null, CancellationToken.None)).ToList();
        var existingRow = rows.Single(m => m.Title == "Noragami");
        newcomer.FranchiseId.Should().NotBeNull();
        existingRow.FranchiseId.Should().Be(newcomer.FranchiseId);
        newcomer.FranchiseOrder.Should().Be(2);
        existingRow.FranchiseOrder.Should().Be(1);
    }
}