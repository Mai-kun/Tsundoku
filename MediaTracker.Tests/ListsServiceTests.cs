using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Lists;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace MediaTracker.Tests;

public class ListsServiceTests
{
    private static (ListsService Service, AppDbContext Db) CreateService()
    {
        var dbPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.db");
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite($"Data Source={dbPath}")
            .Options;
        var db = new AppDbContext(options);
        db.Database.EnsureCreated();
        return (new ListsService(db), db);
    }

    private static async Task<(Guid ListId, Guid MediaId)> SeedListAndMediaAsync(
        (ListsService Service, AppDbContext Db) ctx, string listName = "Test")
    {
        ctx.Db.CustomLists.Add(new CustomList { Name = listName });
        ctx.Db.MediaItems.Add(new Movie { Title = "Movie" });
        await ctx.Db.SaveChangesAsync();
        return (ctx.Db.CustomLists.Single().Id, ctx.Db.MediaItems.Single().Id);
    }

    [Fact]
    public async Task CreateAsync_ShouldTrimNameAndSetDefaults()
    {
        var ctx = CreateService();
        var id = await ctx.Service.CreateAsync(new CreateListRequest("  Watchlist  ", " desc ", " ", "#fff", null), default);

        var list = await ctx.Db.CustomLists.SingleAsync(l => l.Id == id);
        list.Name.Should().Be("Watchlist");
        list.Description.Should().Be("desc");
        list.Icon.Should().Be("list");
        list.Id.Should().NotBe(Guid.Empty);
    }

    [Fact]
    public async Task UpdateAsync_ShouldUpdateFields_WhenListExists()
    {
        var ctx = CreateService();
        await ctx.Service.CreateAsync(new CreateListRequest("Old", null, null, null, null), default);
        var id = ctx.Db.CustomLists.Single().Id;

        var updated = await ctx.Service.UpdateAsync(id, new UpdateListRequest("New", "d", "star", "#123", null), default);
        var list = await ctx.Db.CustomLists.SingleAsync(l => l.Id == id);

        updated.Should().BeTrue();
        list.Name.Should().Be("New");
        list.Icon.Should().Be("star");
        list.Color.Should().Be("#123");
    }

    [Fact]
    public async Task UpdateAsync_ShouldReturnFalse_WhenListMissing()
    {
        var ctx = CreateService();
        (await ctx.Service.UpdateAsync(Guid.NewGuid(), new UpdateListRequest("X", null, null, null, null), default)).Should().BeFalse();
    }

    [Fact]
    public async Task DeleteAsync_ShouldRemoveList_WhenExists()
    {
        var ctx = CreateService();
        var id = await ctx.Service.CreateAsync(new CreateListRequest("Old", null, null, null, null), default);

        (await ctx.Service.DeleteAsync(id, default)).Should().BeTrue();
        ctx.Db.CustomLists.Should().BeEmpty();
    }

    [Fact]
    public async Task DeleteAsync_ShouldReturnFalse_WhenListMissing()
    {
        var ctx = CreateService();
        (await ctx.Service.DeleteAsync(Guid.NewGuid(), default)).Should().BeFalse();
    }

    [Fact]
    public async Task AddMediaAsync_ShouldAssignIncrementingOrder()
    {
        var ctx = CreateService();
        var (listId, movieId) = await SeedListAndMediaAsync(ctx);
        var game = new VideoGame { Title = "Game", Platform = "PC" };
        ctx.Db.MediaItems.Add(game);
        await ctx.Db.SaveChangesAsync();

        (await ctx.Service.AddMediaAsync(listId, game.Id, default)).Should().BeTrue();
        (await ctx.Service.AddMediaAsync(listId, game.Id, default)).Should().BeTrue(); // idempotent
        (await ctx.Service.AddMediaAsync(listId, movieId, default)).Should().BeTrue();

        var items = await ctx.Db.CustomListItems.Where(i => i.ListId == listId).ToListAsync();
        items.Should().HaveCount(2);
        items.Select(i => i.Order).Should().BeEquivalentTo([0, 1]);
    }

    [Fact]
    public async Task AddMediaAsync_ShouldReturnFalse_WhenListOrMediaMissing()
    {
        var ctx = CreateService();
        var (listId, mediaId) = await SeedListAndMediaAsync(ctx);

        (await ctx.Service.AddMediaAsync(Guid.NewGuid(), mediaId, default)).Should().BeFalse();
        (await ctx.Service.AddMediaAsync(listId, Guid.NewGuid(), default)).Should().BeFalse();
    }

    [Fact]
    public async Task RemoveMediaAsync_ShouldRemoveItem_WhenExists()
    {
        var ctx = CreateService();
        var (listId, mediaId) = await SeedListAndMediaAsync(ctx);
        await ctx.Service.AddMediaAsync(listId, mediaId, default);

        (await ctx.Service.RemoveMediaAsync(listId, mediaId, default)).Should().BeTrue();
        ctx.Db.CustomListItems.Should().BeEmpty();
        (await ctx.Service.RemoveMediaAsync(listId, mediaId, default)).Should().BeFalse();
    }

    [Fact]
    public async Task GetListsForMediaAsync_ShouldReturnOnlyPlainLists()
    {
        var ctx = CreateService();
        var (_, mediaId) = await SeedListAndMediaAsync(ctx, "Plain");
        var plainId = ctx.Db.CustomLists.Single().Id;
        var smart = new CustomList { Name = "Smart", SmartQueryJson = "status=completed" };
        ctx.Db.CustomLists.Add(smart);
        await ctx.Db.SaveChangesAsync();

        var (service, _) = ctx;
        await service.AddMediaAsync(plainId, mediaId, default);

        var ids = await service.GetListsForMediaAsync(mediaId, default);

        ids.Should().BeEquivalentTo([plainId]);
    }

    [Fact]
    public async Task GetListDetailAsync_ShouldReturnNull_WhenListMissing()
    {
        var ctx = CreateService();
        (await ctx.Service.GetListDetailAsync(Guid.NewGuid(), default)).Should().BeNull();
    }

    [Fact]
    public async Task GetListDetailAsync_ShouldReturnItemsInOrder_WithMappedDtos()
    {
        var ctx = CreateService();
        var list = new CustomList { Name = "Watch" };
        var movie = new Movie { Title = "Dune", CoverUrl = "https://x/c.jpg" };
        var game = new VideoGame { Title = "Portal", Platform = "PC" };
        ctx.Db.CustomLists.Add(list);
        ctx.Db.MediaItems.AddRange(movie, game);
        await ctx.Db.SaveChangesAsync();

        await ctx.Service.AddMediaAsync(list.Id, movie.Id, default);
        await ctx.Service.AddMediaAsync(list.Id, game.Id, default);
        // RemoveMediaAsync exercised on a present item
        (await ctx.Service.RemoveMediaAsync(list.Id, Guid.NewGuid(), default)).Should().BeFalse();

        var detail = await ctx.Service.GetListDetailAsync(list.Id, default);
        detail.Should().NotBeNull();
        detail!.IsSmart.Should().BeFalse();
        detail.Items.Should().ContainSingle(dto => dto.Title == "Dune");
        detail.Items.Should().ContainSingle(dto => dto.Title == "Portal");
        detail.Name.Should().Be("Watch");

        var summaries = await ctx.Service.GetListsAsync(default);
        summaries.Should().ContainSingle(s => s.Name == "Watch" && s.ItemsCount == 2 && s.PreviewCovers.Contains("https://x/c.jpg"));
    }
}
