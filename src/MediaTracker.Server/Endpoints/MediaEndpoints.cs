using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
using MediaTracker.Server.Services.Franchises;
using MediaTracker.Server.Services.Media;
using MediaTracker.Server.Services.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Endpoints;

public static class MediaEndpoints
{
    private const string Discriminator = "MediaType";
    private static readonly TimeSpan EnrichmentTimeout = TimeSpan.FromSeconds(8);

    public static IEndpointRouteBuilder MapMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media");

        group.MapGet("/", GetMediaItems);
        group.MapGet("/stats", GetMediaStats);
        group.MapGet("/{id:guid}", GetMediaItem);
        group.MapPost("/", CreateMediaItem);
        group.MapPut("/{id:guid}", UpdateMediaItem);
        group.MapPut("/{id:guid}/status", UpdateStatus);
        group.MapPut("/{id:guid}/progress", UpdateProgress);
        group.MapPost("/{id:guid}/refresh", RefreshMediaMetadata);
        group.MapPost("/{id:guid}/enrich", EnrichMediaItem);
        group.MapDelete("/{id:guid}", DeleteMediaItem);

        var historyGroup = app.MapGroup("/api/history");
        historyGroup.MapDelete("/", ClearAllHistory);
        historyGroup.MapDelete("/{id:guid}/{kind}", DeleteHistoryEntry);

        return app;
    }

    private static async Task<IResult> GetMediaItems(
        AppDbContext db,
        string? type = null,
        MediaStatus? status = null,
        bool? isAnime = null,
        string? search = null,
        string? sortBy = "createdAt",
        string? sortOrder = "desc",
        CancellationToken ct = default)
    {
        if (!MediaListQuery.TryBuild(db, type, status, isAnime, search, sortBy, sortOrder, out var query))
        {
            return Results.Ok(Array.Empty<MediaListDto>());
        }

        var rows = await query.ToListAsync(ct);
        var items = new List<MediaListDto>(rows.Count);

        foreach (var row in rows)
        {
            items.Add(WithCoverVersion(row.Item, row.UpdatedAt));
        }

        return Results.Ok(items);
    }

    /// <summary>
    /// Covers are served as immutable for a year, so the cache-buster is part of the URL. The tick
    /// count cannot be produced in SQL, so it is stamped here on the already-projected DTO.
    /// </summary>
    private static MediaListDto WithCoverVersion(MediaListDto dto, DateTime updatedAt) =>
        dto.CoverUrl is null ? dto : dto with { CoverUrl = $"{dto.CoverUrl}?v={updatedAt.Ticks}" };

    private static async Task<IResult> GetMediaStats(AppDbContext db, CancellationToken ct)
    {
        // One grouped scan over MediaItems yields every per-type count and sum the dashboard shows,
        // instead of the five separate round-trips this endpoint used to issue.
        var totals = await db.MediaItems
            .AsNoTracking()
            .GroupBy(_ => 1)
            .Select(g => new
            {
                Total = g.Count(),
                Completed = g.Sum(x => x.Status == MediaStatus.Completed ? 1 : 0),
                InProgress = g.Sum(x => x.Status == MediaStatus.InProgress ? 1 : 0),
                Planned = g.Sum(x => x.Status == MediaStatus.Planned ? 1 : 0),
                CompletedGames = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Game" ? 1 : 0),
                CompletedBooks = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Book" ? 1 : 0),
                CompletedMovies = g.Sum(x => x.Status == MediaStatus.Completed && EF.Property<string>(x, Discriminator) == "Movie" ? 1 : 0),
                TotalHoursPlayed = g.Sum(x => x is VideoGame ? ((VideoGame)x).HoursPlayed ?? 0 : 0),
                TotalPagesRead = g.Sum(x => x is Book ? ((Book)x).CurrentPage : 0),
                TotalChaptersRead = g.Sum(x => x is Manga ? ((Manga)x).CurrentChapter : 0),
            })
            .FirstOrDefaultAsync(ct);

        var totalEpisodesWatched = await db.TvSeasons
            .AsNoTracking()
            .SumAsync(season => season.CurrentEpisode, ct);

        var stats = new MediaStatsDto
        {
            TotalItems = totals?.Total ?? 0,
            CompletedItems = totals?.Completed ?? 0,
            InProgressItems = totals?.InProgress ?? 0,
            PlannedItems = totals?.Planned ?? 0,
            CompletedGamesCount = totals?.CompletedGames ?? 0,
            CompletedBooksCount = totals?.CompletedBooks ?? 0,
            CompletedMoviesCount = totals?.CompletedMovies ?? 0,
            TotalHoursPlayed = totals?.TotalHoursPlayed ?? 0,
            TotalPagesRead = totals?.TotalPagesRead ?? 0,
            TotalChaptersRead = totals?.TotalChaptersRead ?? 0,
            TotalEpisodesWatched = totalEpisodesWatched,
        };

        return Results.Ok(stats);
    }

    private static IQueryable<MediaItem> LoadTrackedItemQuery(AppDbContext db) =>
        db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber));

    private static string ResolveAggregatorType(MediaItem item) =>
        item is TvShow { IsAnime: true } or Movie { IsAnime: true }
            ? "anime"
            : MediaResponseMapper.GetType(item);

    private static int ClampToKnownTotal(int current, int? total) =>
        total is > 0 ? Math.Min(current, total.Value) : current;
    private static async Task<IResult> GetMediaItem(Guid id, AppDbContext db, CancellationToken ct)
    {
        var item = await LoadTrackedItemQuery(db).SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        if (item is Manga manga && EnsureMangaHasFirstVolume(manga))
        {
            await db.SaveChangesAsync(ct);
        }

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
    }

    /// <summary>
    /// Seeds the first volume for a manga that has none, so the detail view always has a row to
    /// render. Returns true when the stub was created.
    /// </summary>
    private static bool EnsureMangaHasFirstVolume(Manga manga)
    {
        if (manga.Volumes.Count > 0)
        {
            return false;
        }

        manga.Volumes.Add(new MangaVolume
        {
            Id = Guid.NewGuid(),
            MangaId = manga.Id,
            VolumeNumber = 1,
            Title = "Volume 1",
            TotalPages = 200,
            TotalChapters = manga.TotalChapters is > 0 ? manga.TotalChapters.Value : 0,
            CurrentPage = 0,
            Status = manga.Status
        });

        if (manga.TotalVolumes is null or 0)
        {
            manga.TotalVolumes = 1;
        }

        if (manga.CurrentVolume <= 0)
        {
            manga.CurrentVolume = 1;
        }

        return true;
    }

    private static async Task<IResult> EnrichMediaItem(
        Guid id,
        AppDbContext db,
        MetadataAggregatorService aggregator,
        ILoggerFactory loggerFactory,
        CancellationToken ct)
    {
        var logger = loggerFactory.CreateLogger(typeof(MediaEndpoints));
        var item = await LoadTrackedItemQuery(db).SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        try
        {
            // Enrichment is a background quality pass: a slow or broken provider must not fail the
            // request, the user still gets the item they asked for.
            using var enrichCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            enrichCts.CancelAfter(EnrichmentTimeout);

            var external = await aggregator.GetDetailsAsync(
                ResolveAggregatorType(item), item.ExternalId ?? string.Empty, item.Title, enrichCts.Token, item.ExternalSource);

            if (external is not null && MediaMetadataApplier.ApplyIfMissing(item, external))
            {
                item.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning("Enrichment for media {MediaId} timed out after {Timeout}", id, EnrichmentTimeout);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Enrichment for media {MediaId} failed, returning the item unchanged", id);
        }

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
    }

    private static async Task<IResult> CreateMediaItem(
        CreateMediaRequest request,
        AppDbContext db,
        IValidator<CreateMediaRequest> validator,
        IImageStorageService imageStorage,
        IFranchiseService franchiseService,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var item = MediaItemFactory.CreateEntity(request);

        if (MediaMetadataApplier.IsExternalUrl(item.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(item.CoverUrl!, item.Id, ct);
        }

        MediaCollectionSeeder.SeedPlaceholderSeasons(item, request);
        MediaCollectionSeeder.SeedPlaceholderVolumes(item, request);

        await franchiseService.LinkFranchiseOnCreateAsync(db, item, request.FranchiseName, ct);

        db.Add(item);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/media/{item.Id}", MediaResponseMapper.ToDetailDto(item));
    }

    private static async Task<IResult> UpdateMediaItem(
        Guid id,
        UpdateMediaRequest request,
        AppDbContext db,
        IValidator<UpdateMediaRequest> validator,
        IFranchiseService franchiseService,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var item = await LoadTrackedItemQuery(db).SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        MediaItemUpdater.Apply(item, request);
        await franchiseService.LinkFranchiseOnUpdateAsync(db, item, request.FranchiseId, request.FranchiseName, ct);

        item.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
    }

    private static async Task<IResult> UpdateStatus(
        Guid id,
        UpdateStatusRequest request,
        AppDbContext db,
        IValidator<UpdateStatusRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var item = await db.MediaItems
            .Include(media => ((TvShow)media).Seasons)
            .SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        item.Status = request.Status;
        MediaStatusTransitions.Apply(item, request.Status);
        item.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> ClearAllHistory(AppDbContext db, CancellationToken ct)
    {
        await db.MediaItems.ExecuteUpdateAsync(s => s
            .SetProperty(m => m.StartedAt, (DateTime?)null)
            .SetProperty(m => m.FinishedAt, (DateTime?)null), ct);
        return Results.NoContent();
    }

    private static async Task<IResult> DeleteHistoryEntry(
        Guid id,
        string kind,
        AppDbContext db,
        CancellationToken ct)
    {
        var item = await db.MediaItems.FindAsync([id], ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        if (IsHistoryKind(kind, "started"))
        {
            item.StartedAt = null;
        }
        else if (IsHistoryKind(kind, "finished"))
        {
            item.FinishedAt = null;
        }
        else
        {
            return Results.BadRequest(new { message = "Kind must be 'started' or 'finished'." });
        }

        item.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static bool IsHistoryKind(string kind, string expected) =>
        string.Equals(kind.Trim(), expected, StringComparison.OrdinalIgnoreCase);

    private static async Task<IResult> UpdateProgress(
        Guid id,
        UpdateProgressRequest request,
        AppDbContext db,
        IValidator<UpdateProgressRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var progress = Math.Max(request.CurrentProgress, 0);

        // The clamping total and the row type live in the same table, so the whole stepper write is a
        // single UPDATE: no SELECT, no entity materialization, no change tracker entry.
        var bookRows = await db.Books
            .Where(x => x.Id == id)
            .ExecuteUpdateAsync(
                s => s.SetProperty(
                    x => x.CurrentPage,
                    x => x.TotalPages > 0 && progress > x.TotalPages ? x.TotalPages : progress),
                ct);

        if (bookRows > 0)
        {
            return Results.NoContent();
        }

        var mangaRows = await db.Manga
            .Where(x => x.Id == id)
            .ExecuteUpdateAsync(
                s => s.SetProperty(
                    x => x.CurrentChapter,
                    x => x.TotalChapters != null && progress > x.TotalChapters ? x.TotalChapters : progress),
                ct);

        if (mangaRows > 0)
        {
            return Results.NoContent();
        }

        var gameRows = await db.Games
            .Where(x => x.Id == id)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.HoursPlayed, progress), ct);

        return gameRows > 0
            ? Results.NoContent()
            : Results.BadRequest("Progress is not supported for this media type.");
    }

    private static async Task<IResult> RefreshMediaMetadata(
        Guid id,
        AppDbContext db,
        MetadataAggregatorService metadataAggregator,
        IImageStorageService imageStorage,
        CancellationToken ct)
    {
        var item = await LoadTrackedItemQuery(db).SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        var external = await metadataAggregator.GetDetailsAsync(
            ResolveAggregatorType(item), item.ExternalId ?? string.Empty, item.Title, ct, item.ExternalSource);

        if (external is null)
        {
            return Results.NotFound(new { message = "Metadata could not be found from external source." });
        }

        await MediaMetadataApplier.ApplyOverwriteAsync(item, external, imageStorage, ct);

        item.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
    }

    private static async Task<IResult> DeleteMediaItem(
        Guid id,
        AppDbContext db,
        IImageStorageService imageStorage,
        CancellationToken ct)
    {
        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        imageStorage.DeleteCover(item.CoverUrl);

        db.MediaItems.Remove(item);
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

}
