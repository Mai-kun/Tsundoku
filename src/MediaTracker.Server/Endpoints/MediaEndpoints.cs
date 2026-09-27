using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using MediaTracker.Server.Services.External;
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
        group.MapGet("/stats", GetMediaStats);
        group.MapGet("/{id:guid}", GetMediaItem);
        group.MapPost("/", CreateMediaItem);
        group.MapPut("/{id:guid}", UpdateMediaItem);
        group.MapPut("/{id:guid}/status", UpdateStatus);
        group.MapPut("/{id:guid}/progress", UpdateProgress);
        group.MapPost("/{id:guid}/refresh", RefreshMediaMetadata);
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
        string? sortBy = "createdAt",
        string? sortOrder = "desc",
        CancellationToken ct = default)
    {
        IQueryable<MediaItem> query = db.MediaItems
            .AsNoTracking()
            .Include(media => ((TvShow)media).Seasons);

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

        var ascending = string.Equals(sortOrder, "asc", StringComparison.OrdinalIgnoreCase);
        query = sortBy?.Trim().ToLowerInvariant() switch
        {
            "score" => ascending
                ? query.OrderBy(item => item.Score == null).ThenBy(item => item.Score)
                : query.OrderBy(item => item.Score == null).ThenByDescending(item => item.Score),
            "title" => ascending
                ? query.OrderBy(item => item.Title)
                : query.OrderByDescending(item => item.Title),
            _ => ascending
                ? query.OrderBy(item => item.CreatedAt)
                : query.OrderByDescending(item => item.CreatedAt),
        };

        var items = await query.ToListAsync(ct);
        return Results.Ok(items.Select(MediaResponseMapper.ToListDto));
    }

    private static async Task<IResult> GetMediaStats(AppDbContext db, CancellationToken ct)
    {
        var stats = new MediaStatsDto
        {
            TotalItems = await db.MediaItems.CountAsync(ct),
            CompletedItems = await db.MediaItems.CountAsync(item => item.Status == MediaStatus.Completed, ct),
            InProgressItems = await db.MediaItems.CountAsync(item => item.Status == MediaStatus.InProgress, ct),
            PlannedItems = await db.MediaItems.CountAsync(item => item.Status == MediaStatus.Planned, ct),
            TotalHoursPlayed = await db.Games.SumAsync(game => game.HoursPlayed ?? 0, ct),
            TotalPagesRead = await db.Books.SumAsync(book => book.CurrentPage, ct),
            TotalChaptersRead = await db.Manga.SumAsync(manga => manga.CurrentChapter, ct),
            TotalEpisodesWatched = await db.TvSeasons.SumAsync(season => season.CurrentEpisode, ct),
            CompletedGamesCount = await db.Games.CountAsync(game => game.Status == MediaStatus.Completed, ct),
            CompletedBooksCount = await db.Books.CountAsync(book => book.Status == MediaStatus.Completed, ct),
            CompletedMoviesCount = await db.Movies.CountAsync(movie => movie.Status == MediaStatus.Completed, ct),
        };

        return Results.Ok(stats);
    }

    private static async Task<IResult> GetMediaItem(Guid id, AppDbContext db, CancellationToken ct)
    {
        var item = await db.MediaItems
            .AsNoTracking()
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .SingleOrDefaultAsync(media => media.Id == id, ct);

        return item is null ? Results.NotFound() : Results.Ok(MediaResponseMapper.ToDetailDto(item));
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

        if (item is TvShow { IsAnime: true } animeShow && animeShow.Seasons.Count == 0)
        {
            var epCount = request.DurationMinutes ?? request.TotalPages ?? request.TotalChapters ?? 0;
            if (epCount > 0)
            {
                animeShow.Seasons.Add(new TvSeason
                {
                    SeasonNumber = 1,
                    Title = "Season 1",
                    TotalEpisodes = epCount,
                    Status = animeShow.Status
                });
            }
        }

        db.Add(item);
        await db.SaveChangesAsync(ct);

        return Results.Created($"/api/media/{item.Id}", MediaResponseMapper.ToDetailDto(item));
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

        var item = await db.MediaItems
            .Include(media => ((TvShow)media).Seasons)
            .SingleOrDefaultAsync(media => media.Id == id, ct);
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
        if (request.Status == MediaStatus.Completed)
        {
            item.FinishedAt ??= DateTime.UtcNow;
            if (item.StartedAt is null) item.StartedAt = DateTime.UtcNow;

            if (item is TvShow show)
            {
                foreach (var season in show.Seasons)
                {
                    season.CurrentEpisode = season.TotalEpisodes;
                    season.Status = MediaStatus.Completed;
                }
            }
            else if (item is Book book && book.TotalPages > 0)
            {
                book.CurrentPage = book.TotalPages;
            }
            else if (item is Manga manga && manga.TotalChapters is > 0)
            {
                manga.CurrentChapter = manga.TotalChapters.Value;
            }
        }
        else if (request.Status == MediaStatus.Planned)
        {
            item.FinishedAt = null;
        }

        item.UpdatedAt = DateTime.UtcNow;
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

        var target = await db.MediaItems
            .Where(x => x.Id == id)
            .Select(x => new
            {
                IsBook = x is Book,
                BookTotal = x is Book ? ((Book)x).TotalPages : (int?)null,
                IsManga = x is Manga,
                MangaTotal = x is Manga ? ((Manga)x).TotalChapters : (int?)null,
                IsGame = x is VideoGame
            })
            .FirstOrDefaultAsync(ct);

        if (target is null)
        {
            return Results.NotFound();
        }

        var currentProgress = Math.Max(request.CurrentProgress, 0);

        if (target.IsBook)
        {
            var clamped = ClampToKnownTotal(currentProgress, target.BookTotal);
            await db.Books.Where(x => x.Id == id)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CurrentPage, clamped), ct);
        }
        else if (target.IsManga)
        {
            var clamped = ClampToKnownTotal(currentProgress, target.MangaTotal);
            await db.Manga.Where(x => x.Id == id)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.CurrentChapter, clamped), ct);
        }
        else if (target.IsGame)
        {
            await db.Games.Where(x => x.Id == id)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.HoursPlayed, currentProgress), ct);
        }
        else
        {
            return Results.BadRequest("Progress is not supported for this media type.");
        }

        return Results.NoContent();
    }

    private static async Task<IResult> RefreshMediaMetadata(
        Guid id,
        AppDbContext db,
        MetadataAggregatorService metadataAggregator,
        IImageStorageService imageStorage,
        CancellationToken ct)
    {
        var item = await db.MediaItems
            .Include(media => ((TvShow)media).Seasons)
            .SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        var type = MediaResponseMapper.GetType(item);
        if (item is TvShow { IsAnime: true } or Movie { IsAnime: true })
        {
            type = "anime";
        }

        var external = await metadataAggregator.GetDetailsAsync(type, item.ExternalId ?? "", item.Title, ct);
        if (external is null)
        {
            return Results.NotFound(new { message = "Metadata could not be found from external source." });
        }

        item.Title = external.Title;
        if (!string.IsNullOrWhiteSpace(external.Description))
        {
            item.Notes = external.Description;
        }

        if (IsExternalUrl(external.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(external.CoverUrl!, item.Id, ct);
        }

        item.ExternalId = external.ExternalId;
        item.ExternalSource = external.ExternalSource ?? item.ExternalSource;
        item.ExternalRating = external.Rating;
        item.ExternalRatingVotes = external.RatingVotes;
        if (external.Ratings is { Count: > 0 })
        {
            item.ExternalRatingsJson = System.Text.Json.JsonSerializer.Serialize(external.Ratings);
        }

        if (item is TvShow show)
        {
            if (!string.IsNullOrWhiteSpace(external.Studio))
            {
                show.Studio = external.Studio;
                show.Network = external.Studio;
            }
            if (!string.IsNullOrWhiteSpace(external.OriginalTitle))
            {
                show.RomajiTitle = external.OriginalTitle;
            }

            if (show.IsAnime && external.Episodes is { Count: > 0 } epList)
            {
                var season = show.Seasons.FirstOrDefault();
                if (season is null)
                {
                    season = new TvSeason
                    {
                        Id = Guid.NewGuid(),
                        SeasonNumber = 1,
                        Title = "Season 1",
                        TvShowId = show.Id,
                        Status = show.Status,
                        TotalEpisodes = external.TotalCount ?? epList.Count,
                        EpisodesData = System.Text.Json.JsonSerializer.Serialize(epList)
                    };
                    show.Seasons.Add(season);
                }
                else
                {
                    season.TotalEpisodes = external.TotalCount ?? epList.Count;
                    season.EpisodesData = System.Text.Json.JsonSerializer.Serialize(epList);
                }
            }
        }
        else if (item is Movie movie)
        {
            if (external.TotalCount is > 0) movie.DurationMinutes = external.TotalCount.Value;
            if (!string.IsNullOrWhiteSpace(external.Studio)) movie.Studio = external.Studio;
            if (!string.IsNullOrWhiteSpace(external.OriginalTitle)) movie.RomajiTitle = external.OriginalTitle;
        }
        else if (item is Book book)
        {
            if (external.TotalCount is > 0) book.TotalPages = external.TotalCount.Value;
            if (!string.IsNullOrWhiteSpace(external.Author)) book.Author = external.Author;
        }
        else if (item is Manga manga)
        {
            if (external.TotalCount is > 0) manga.TotalChapters = external.TotalCount.Value;
        }
        else if (item is VideoGame game)
        {
            if (!string.IsNullOrWhiteSpace(external.Platform)) game.Platform = external.Platform;
        }

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

        season.CurrentEpisode = ClampToKnownTotal(Math.Max(request.CurrentEpisode, 0), season.TotalEpisodes);
        if (season.TotalEpisodes > 0 && season.CurrentEpisode >= season.TotalEpisodes)
        {
            season.Status = MediaStatus.Completed;
        }
        else if (season.CurrentEpisode > 0)
        {
            season.Status = MediaStatus.InProgress;
        }
        else
        {
            season.Status = MediaStatus.Planned;
        }

        var show = await db.TvShows.Include(item => item.Seasons).SingleOrDefaultAsync(item => item.Id == season.TvShowId, ct);
        if (show is not null && show.Seasons.Count > 0)
        {
            var totalWatched = show.Seasons.Sum(item => item.CurrentEpisode);
            var allCompleted = show.Seasons.All(item => item.Status == MediaStatus.Completed);

            if (allCompleted)
            {
                show.Status = MediaStatus.Completed;
                show.FinishedAt ??= DateTime.UtcNow;
                if (show.StartedAt is null) show.StartedAt = DateTime.UtcNow;
            }
            else if (totalWatched > 0)
            {
                if (show.Status == MediaStatus.Completed || show.Status == MediaStatus.Planned)
                {
                    show.Status = MediaStatus.InProgress;
                }
                show.FinishedAt = null;
                if (show.StartedAt is null)
                {
                    show.StartedAt = DateTime.UtcNow;
                }
            }
            else
            {
                // totalWatched == 0 across all seasons
                show.StartedAt = null;
                show.FinishedAt = null;
                if (show.Status == MediaStatus.InProgress || show.Status == MediaStatus.Completed)
                {
                    show.Status = MediaStatus.Planned;
                }
            }
        }

        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }

    private static MediaItem CreateEntity(CreateMediaRequest request)
    {
        MediaItem item = request.Type.Trim().ToLowerInvariant() switch
        {
            "game" => new VideoGame
            {
                Platform = request.Platform ?? string.Empty,
                HoursPlayed = request.HoursPlayed,
                Title = request.Title,
            },
            "book" => new Book
            {
                Author = request.Author ?? string.Empty,
                TotalPages = request.TotalPages ?? 0,
                Title = request.Title,
            },
            "manga" => new Manga
            {
                TotalChapters = request.TotalChapters,
                CurrentVolume = request.CurrentVolume ?? 0,
                Title = request.Title,
            },
            "movie" => new Movie
            {
                DurationMinutes = request.DurationMinutes ?? 0,
                Director = request.Director,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                Title = request.Title,
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
                        EpisodesData = season.EpisodesData,
                    })
                    .ToList() ?? [],
                Title = request.Title,
            },
            _ => throw new UnsupportedMediaTypeException(request.Type),
        };

        item.Status = request.Status;
        item.Score = request.Score;
        item.CoverUrl = request.CoverUrl;
        item.Notes = request.Notes;
        item.FranchiseId = request.FranchiseId;
        item.FranchiseOrder = request.FranchiseOrder;
        item.ExternalId = request.ExternalId;
        item.ExternalSource = request.ExternalSource;
        item.ExternalRating = request.ExternalRating;
        item.ExternalRatingVotes = request.ExternalRatingVotes;
        item.ExternalRatingsJson = request.ExternalRatingsJson;

        return item;
    }

    private static int ClampToKnownTotal(int current, int? total) =>
        total is > 0 ? Math.Min(current, total.Value) : current;

    private static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    private sealed class UnsupportedMediaTypeException(string mediaType)
        : InvalidOperationException($"Unsupported media type '{mediaType}'.");
}
