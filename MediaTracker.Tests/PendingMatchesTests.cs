using FluentAssertions;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.PendingMatches;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Xunit;

namespace MediaTracker.Tests;

public class PendingMatchesTests
{
    private static AppDbContext CreateContext()
    {
        var db = new AppDbContext($"Data Source={Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.db")}");
        db.Database.EnsureCreated();
        return db;
    }

    private static ExternalMediaDto Candidate(string id, string title, string source = "TMDb") => new()
    {
        ExternalId = id,
        Title = title,
        Type = "movie",
        ExternalSource = source,
    };

    [Fact]
    public async Task GetPendingMatches_ShouldMapNeedsReviewRows()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Manga { Title = "Ван Пис", Author = "Oda", RomajiTitle = "One Piece", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([Candidate("m1", "One Piece")]) },
            new Movie { Title = "Akira", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = "not json", IsAnime = true },
            new Book { Title = "Not pending", Author = "x", SyncStatus = SyncStatus.Ready },
            new TvShow { Title = "Lost", SyncStatus = SyncStatus.Syncing });
        await db.SaveChangesAsync();
        var handler = new GetPendingMatchesHandler(db);

        var result = await handler.HandleAsync(CancellationToken.None);

        var manga = result.Should().ContainSingle(d => d.Type == "manga").Subject;
        manga.Title.Should().Be("Ван Пис");
        manga.RomajiTitle.Should().Be("One Piece");
        manga.Candidates.Should().ContainSingle(c => c.ExternalId == "m1");

        var movie = result.Should().ContainSingle(d => d.Title == "Akira").Subject;
        movie.Type.Should().Be("movie");
        movie.IsAnime.Should().BeTrue();
        movie.Candidates.Should().BeEmpty(); // unreadable json degrades to empty
        movie.RomajiTitle.Should().Be("Akira"); // latin extractor fallback
    }

    [Fact]
    public async Task GetPendingMatches_ShouldMapProgressAndTotals()
    {
        using var db = CreateContext();
        var show = new TvShow { Title = "Show", SyncStatus = SyncStatus.NeedsReview };
        show.Seasons.Add(new TvSeason { SeasonNumber = 1, Title = "S1", TotalEpisodes = 12, CurrentEpisode = 8 });
        var game = new VideoGame { Title = "Game", Platform = "PC", SyncStatus = SyncStatus.NeedsReview, HoursPlayed = 42 };
        var book = new Book { Title = "Book", Author = "x", SyncStatus = SyncStatus.NeedsReview, CurrentPage = 150, TotalPages = 310 };
        db.MediaItems.AddRange(show, game, book);
        await db.SaveChangesAsync();
        var handler = new GetPendingMatchesHandler(db);

        var result = await handler.HandleAsync(CancellationToken.None);

        result.Single(d => d.Title == "Show").CurrentProgress.Should().Be(8);
        result.Single(d => d.Title == "Show").TotalCount.Should().Be(12);
        result.Single(d => d.Title == "Game").CurrentProgress.Should().Be(42);
        result.Single(d => d.Title == "Game").TotalCount.Should().BeNull();
        result.Single(d => d.Title == "Book").CurrentProgress.Should().Be(150);
        result.Single(d => d.Title == "Book").TotalCount.Should().Be(310);
    }

    [Fact]
    public async Task ResolveMatch_ShouldRejectInvalidPayloadAndMissingRow()
    {
        using var db = CreateContext();
        var handler = new ResolveMatchHandler(db, jobs: null, logger: null);

        var validation = await handler.HandleAsync(new(Guid.NewGuid(), new ResolveMatchRequest(" ", "", null, null)), CancellationToken.None);
        validation.IsFailure.Should().BeTrue();
        validation.Error!.Type.Should().Be(ErrorType.Validation);

        var missing = await handler.HandleAsync(new(Guid.NewGuid(), new ResolveMatchRequest("1", "TMDb")), CancellationToken.None);
        missing.IsFailure.Should().BeTrue();
        missing.Error!.Type.Should().Be(ErrorType.NotFound);
    }

    [Fact]
    public async Task ResolveMatch_ShouldRecordPick_WithoutBackgroundWork()
    {
        using var db = CreateContext();
        var item = new Movie { Title = "Акира", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([Candidate("akira-1", "Akira")]) };
        db.MediaItems.Add(item);
        await db.SaveChangesAsync();
        var handler = new ResolveMatchHandler(db, jobs: null, logger: null);

        var result = await handler.HandleAsync(new(item.Id, new ResolveMatchRequest("akira-1", "TMDb", "movie", "Akira")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        var reloaded = await db.MediaItems.SingleAsync(m => m.Id == item.Id);
        reloaded.ExternalId.Should().Be("akira-1");
        reloaded.ExternalSource.Should().Be("TMDb");
        reloaded.SyncStatus.Should().Be(SyncStatus.Syncing);
        reloaded.PendingMatchesJson.Should().BeNull();
    }

    [Fact]
    public async Task ResolveAllByPriority_ShouldResolveStrongAndKeepWeak()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            // Exact title match scores high enough for a bulk pick
            new Movie { Title = "Akira", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([new ExternalMediaDto { ExternalId = "t1", Title = "Akira", Type = "movie", ExternalSource = "TMDb" }]) },
            new Movie { Title = "Complete nonsense", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([new ExternalMediaDto { ExternalId = "", Title = "", Type = "movie", ExternalSource = "Rawg" }]) });
        await db.SaveChangesAsync();
        var handler = new ResolveAllByPriorityHandler(db, jobs: null);

        var result = await handler.HandleAsync(CancellationToken.None);

        result.ResolvedCount.Should().Be(1);
        result.SkippedCount.Should().Be(1);
        (await db.MediaItems.SingleAsync(m => m.Title == "Akira")).SyncStatus.Should().Be(SyncStatus.Syncing);
        (await db.MediaItems.SingleAsync(m => m.Title == "Complete nonsense")).SyncStatus.Should().Be(SyncStatus.NeedsReview);
    }

    [Fact]
    public async Task DismissMatch_ShouldResetRowToReady()
    {
        using var db = CreateContext();
        var item = new Movie { Title = "Акира", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([Candidate("1", "Akira")]) };
        db.MediaItems.Add(item);
        await db.SaveChangesAsync();
        var handler = new DismissMatchHandler(db);

        (await handler.HandleAsync(new(item.Id), CancellationToken.None)).Should().BeTrue();
        (await handler.HandleAsync(new(Guid.NewGuid()), CancellationToken.None)).Should().BeFalse();

        var reloaded = await db.MediaItems.SingleAsync(m => m.Id == item.Id);
        reloaded.SyncStatus.Should().Be(SyncStatus.Ready);
        reloaded.PendingMatchesJson.Should().BeNull();
    }

    [Fact]
    public async Task DismissAllMatches_ShouldResetEveryNeedsReviewRow()
    {
        using var db = CreateContext();
        db.MediaItems.AddRange(
            new Movie { Title = "A", SyncStatus = SyncStatus.NeedsReview, PendingMatchesJson = MediaJsonCache.Serialize([Candidate("1", "A")]) },
            new Movie { Title = "B", SyncStatus = SyncStatus.NeedsReview },
            new Movie { Title = "C", SyncStatus = SyncStatus.Ready });
        await db.SaveChangesAsync();
        var handler = new DismissAllMatchesHandler(db);

        var dismissed = await handler.HandleAsync(CancellationToken.None);

        dismissed.Should().Be(2);
        db.ChangeTracker.Clear();
        db.MediaItems.All(m => m.SyncStatus == SyncStatus.Ready).Should().BeTrue();
        db.MediaItems.All(m => m.PendingMatchesJson == null).Should().BeTrue();
    }
}
