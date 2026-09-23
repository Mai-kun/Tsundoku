using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Endpoints;

public static class MediaEndpoints
{
    private const string Discriminator = "MediaType";

    public static IEndpointRouteBuilder MapMediaEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media");

        group.MapGet("/", GetMediaItems);
        group.MapGet("/{id:guid}", GetMediaItem);
        group.MapPost("/", CreateMediaItem);
        group.MapPut("/{id:guid}", UpdateMediaItem);
        group.MapPut("/{id:guid}/status", UpdateStatus);
        group.MapPut("/{id:guid}/progress", UpdateProgress);
        group.MapDelete("/{id:guid}", DeleteMediaItem);

        return app;
    }

    public static IEndpointRouteBuilder MapSeasonEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/seasons");

        group.MapPut("/{id:guid}/progress", UpdateSeasonProgress);

        return app;
    }

    private static async Task<IResult> GetMediaItems(
        AppDbContext db,
        string? type = null,
        MediaStatus? status = null,
        bool? isAnime = null,
        string? search = null,
        CancellationToken ct = default)
    {
        IQueryable<MediaItem> query = db.MediaItems.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(type))
        {
            var discriminator = type.Trim().ToLowerInvariant() switch
            {
                "game" => "Game",
                "book" => "Book",
                "manga" => "Manga",
                "movie" => "Movie",
                "tvshow" => "TvShow",
                _ => null,
            };

            if (discriminator is null)
            {
                return Results.Ok(Array.Empty<MediaItem>());
            }

            query = query.Where(item => EF.Property<string>(item, Discriminator) == discriminator);
        }

        if (status is not null)
        {
            query = query.Where(item => item.Status == status);
        }

        if (isAnime is { } anime)
        {
            query = query.Where(item =>
                (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).IsAnime == anime)
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).IsAnime == anime));
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(item => EF.Functions.Like(item.Title, $"%{search.Trim()}%"));
        }

        var items = await query.ToListAsync(ct);
        return Results.Ok(items);
    }

    private static async Task<IResult> GetMediaItem(Guid id, AppDbContext db, CancellationToken ct)
    {
        var item = await db.MediaItems
            .AsNoTracking()
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .SingleOrDefaultAsync(media => media.Id == id, ct);

        return item is null ? Results.NotFound() : Results.Ok(item);
    }

    private static async Task<IResult> CreateMediaItem(
        CreateMediaRequest request,
        AppDbContext db,
        IValidator<CreateMediaRequest> validator,
        IImageStorageService imageStorage,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var item = CreateEntity(request);
        item.Id = Guid.NewGuid();

        if (IsExternalUrl(item.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(item.CoverUrl!, item.Id, ct);
        }

        db.Add(item);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/media/{item.Id}", item);
    }

    private static async Task<IResult> UpdateMediaItem(
        Guid id,
        UpdateMediaRequest request,
        AppDbContext db,
        IValidator<UpdateMediaRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        item.Title = request.Title ?? item.Title;
        item.Score = request.Score ?? item.Score;

        if (request.Status is { } status)
        {
            item.Status = status;
        }

        if (request.Notes is not null)
        {
            item.Notes = request.Notes;
        }

        if (request.CoverUrl is not null)
        {
            item.CoverUrl = request.CoverUrl;
        }

        if (request.StartedAt is not null)
        {
            item.StartedAt = request.StartedAt;
        }

        if (request.FinishedAt is not null)
        {
            item.FinishedAt = request.FinishedAt;
        }

        await db.SaveChangesAsync(ct);

        return Results.Ok(item);
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

        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        item.Status = request.Status;

        if (item.Status == MediaStatus.Completed && item.FinishedAt is null)
        {
            item.FinishedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

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

        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        switch (item)
        {
            case Book book:
                book.CurrentPage = request.CurrentProgress;
                break;
            case Manga manga:
                manga.CurrentChapter = request.CurrentProgress;
                break;
            case VideoGame game:
                game.HoursPlayed = request.CurrentProgress;
                break;
            default:
                return Results.BadRequest("Progress is not supported for this media type.");
        }

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
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

    private static async Task<IResult> UpdateSeasonProgress(
        Guid id,
        UpdateSeasonProgressRequest request,
        AppDbContext db,
        IValidator<UpdateSeasonProgressRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var season = await db.TvSeasons.SingleOrDefaultAsync(item => item.Id == id, ct);
        if (season is null)
        {
            return Results.NotFound();
        }

        season.CurrentEpisode = request.CurrentEpisode;

        if (season.CurrentEpisode >= season.TotalEpisodes)
        {
            season.Status = MediaStatus.Completed;
        }

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

    private static MediaItem CreateEntity(CreateMediaRequest request) =>
        request.Type.Trim().ToLowerInvariant() switch
        {
            "game" => new VideoGame
            {
                Platform = request.Platform ?? string.Empty,
                HoursPlayed = request.HoursPlayed,
                Title = request.Title,
                Status = request.Status,
                Score = request.Score,
                CoverUrl = request.CoverUrl,
                Notes = request.Notes,
                FranchiseId = request.FranchiseId,
                FranchiseOrder = request.FranchiseOrder,
            },
            "book" => new Book
            {
                Author = request.Author ?? string.Empty,
                TotalPages = request.TotalPages ?? 0,
                Title = request.Title,
                Status = request.Status,
                Score = request.Score,
                CoverUrl = request.CoverUrl,
                Notes = request.Notes,
                FranchiseId = request.FranchiseId,
                FranchiseOrder = request.FranchiseOrder,
            },
            "manga" => new Manga
            {
                TotalChapters = request.TotalChapters,
                CurrentVolume = request.CurrentVolume ?? 0,
                Title = request.Title,
                Status = request.Status,
                Score = request.Score,
                CoverUrl = request.CoverUrl,
                Notes = request.Notes,
                FranchiseId = request.FranchiseId,
                FranchiseOrder = request.FranchiseOrder,
            },
            "movie" => new Movie
            {
                DurationMinutes = request.DurationMinutes ?? 0,
                Director = request.Director,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                Title = request.Title,
                Status = request.Status,
                Score = request.Score,
                CoverUrl = request.CoverUrl,
                Notes = request.Notes,
                FranchiseId = request.FranchiseId,
                FranchiseOrder = request.FranchiseOrder,
            },
            "tvshow" => new TvShow
            {
                Network = request.Network,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                Seasons = request.Seasons?
                    .Select(season => new TvSeason
                    {
                        SeasonNumber = season.SeasonNumber,
                        Title = season.Title,
                        CoverUrl = season.CoverUrl,
                        TotalEpisodes = season.TotalEpisodes,
                        Status = season.Status,
                        Score = season.Score,
                        Notes = season.Notes,
                        AirDate = season.AirDate,
                    })
                    .ToList() ?? [],
                Title = request.Title,
                Status = request.Status,
                Score = request.Score,
                CoverUrl = request.CoverUrl,
                Notes = request.Notes,
                FranchiseId = request.FranchiseId,
                FranchiseOrder = request.FranchiseOrder,
            },
            _ => throw new UnsupportedMediaTypeException(request.Type),
        };

    private static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    private sealed class UnsupportedMediaTypeException(string mediaType)
        : InvalidOperationException($"Unsupported media type '{mediaType}'.");
}