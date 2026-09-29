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
        group.MapPost("/{id:guid}/enrich", EnrichMediaItem);
        group.MapDelete("/{id:guid}", DeleteMediaItem);

        return app;
    }

    public static IEndpointRouteBuilder MapSeasonEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/seasons");

        group.MapPut("/{id:guid}/progress", UpdateSeasonProgress);

        return app;
    }

    public static IEndpointRouteBuilder MapVolumeEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/volumes");

        group.MapPut("/{id:guid}/progress", UpdateVolumeProgress);
        group.MapPost("/", AddVolume);
        group.MapPut("/{id:guid}", UpdateVolume);
        group.MapDelete("/{id:guid}", DeleteVolume);

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
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons)
            .Include(media => ((Manga)media).Volumes);

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
            var term = search.Trim();
            query = query.Where(item =>
                EF.Functions.Like(item.Title, $"%{term}%")
                || (item.Franchise != null && EF.Functions.Like(item.Franchise.Name, $"%{term}%"))
                || (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).RomajiTitle != null && EF.Functions.Like(((Movie)item).RomajiTitle!, $"%{term}%"))
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).RomajiTitle != null && EF.Functions.Like(((TvShow)item).RomajiTitle!, $"%{term}%")));
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
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
            .SingleOrDefaultAsync(media => media.Id == id, ct);

        if (item is null) return Results.NotFound();

        if (item is Manga manga && manga.Volumes.Count == 0)
        {
            var vol = new MangaVolume
            {
                Id = Guid.NewGuid(),
                MangaId = manga.Id,
                VolumeNumber = 1,
                Title = "Volume 1",
                TotalPages = 200,
                TotalChapters = manga.TotalChapters is > 0 ? manga.TotalChapters.Value : 0,
                CurrentPage = 0,
                Status = manga.Status
            };
            manga.Volumes.Add(vol);
            if (manga.TotalVolumes is null or 0) manga.TotalVolumes = 1;
            if (manga.CurrentVolume <= 0) manga.CurrentVolume = 1;
            await db.SaveChangesAsync(ct);
        }

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
    }

    private static async Task<IResult> EnrichMediaItem(
        Guid id,
        AppDbContext db,
        MetadataAggregatorService aggregator,
        CancellationToken ct)
    {
        var item = await db.MediaItems
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons.OrderBy(season => season.SeasonNumber))
            .Include(media => ((Manga)media).Volumes.OrderBy(volume => volume.VolumeNumber))
            .SingleOrDefaultAsync(media => media.Id == id, ct);

        if (item is null) return Results.NotFound();

        var itemType = MediaResponseMapper.GetType(item);
        if (item is TvShow { IsAnime: true } or Movie { IsAnime: true })
        {
            itemType = "anime";
        }

        try
        {
            using var enrichCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            enrichCts.CancelAfter(TimeSpan.FromSeconds(8));
            var enriched = await aggregator.GetDetailsAsync(
                itemType, item.ExternalId ?? "", item.Title, enrichCts.Token, item.ExternalSource);

            if (enriched is not null)
            {
                bool modified = false;

                if (enriched.Ratings is { Count: > 0 } ratings)
                {
                    item.ExternalRatingsJson = System.Text.Json.JsonSerializer.Serialize(
                        ratings.Select(r => new { source = r.Source, score = r.Rating, votes = r.Votes }));
                    if (enriched.Rating.HasValue && enriched.Rating.Value > 0)
                    {
                        item.ExternalRating = enriched.Rating.Value;
                        item.ExternalRatingVotes = enriched.RatingVotes;
                    }
                    modified = true;
                }

                if (item is Manga manga)
                {
                    if (enriched.Chapters.HasValue && (!manga.TotalChapters.HasValue || manga.TotalChapters.Value <= 0))
                    {
                        manga.TotalChapters = enriched.Chapters.Value;
                        modified = true;
                    }
                    if (enriched.Volumes.HasValue && (!manga.TotalVolumes.HasValue || manga.TotalVolumes.Value <= 0))
                    {
                        manga.TotalVolumes = enriched.Volumes.Value;
                        modified = true;
                    }
                    if (string.IsNullOrWhiteSpace(manga.Author) && !string.IsNullOrWhiteSpace(enriched.Author))
                    {
                        manga.Author = enriched.Author;
                        modified = true;
                    }
                    if (string.IsNullOrWhiteSpace(manga.RomajiTitle) && !string.IsNullOrWhiteSpace(enriched.RomajiTitle))
                    {
                        manga.RomajiTitle = enriched.RomajiTitle;
                        modified = true;
                    }
                    if (manga.Volumes.Count == 1 && manga.Volumes[0].TotalChapters == 0 && manga.TotalChapters is > 0)
                    {
                        manga.Volumes[0].TotalChapters = manga.TotalChapters.Value;
                        modified = true;
                    }
                }

                if (string.IsNullOrWhiteSpace(item.Notes) && !string.IsNullOrWhiteSpace(enriched.Description))
                {
                    item.Notes = enriched.Description;
                    modified = true;
                }

                if (modified)
                {
                    item.UpdatedAt = DateTime.UtcNow;
                    await db.SaveChangesAsync(ct);
                }
            }
        }
        catch { }

        return Results.Ok(MediaResponseMapper.ToDetailDto(item));
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

        if (item is Manga mangaItem && mangaItem.Volumes.Count == 0)
        {
            var totalVols = request.TotalVolumes is > 0 ? Math.Min(request.TotalVolumes.Value, 200) : 1;
            for (var i = 1; i <= totalVols; i++)
            {
                var chaptersInVol = request.TotalChapters.HasValue && totalVols > 0
                    ? (int)Math.Ceiling((double)request.TotalChapters.Value / totalVols)
                    : 0;
                var pagesInVol = request.TotalPages.HasValue && totalVols > 0
                    ? (int)Math.Ceiling((double)request.TotalPages.Value / totalVols)
                    : 200;

                mangaItem.Volumes.Add(new MangaVolume
                {
                    VolumeNumber = i,
                    Title = $"Volume {i}",
                    TotalChapters = chaptersInVol,
                    TotalPages = pagesInVol,
                    Status = mangaItem.Status
                });
            }

            if (mangaItem.TotalVolumes is null or 0)
            {
                mangaItem.TotalVolumes = totalVols;
            }
            if (mangaItem.CurrentVolume <= 0)
            {
                mangaItem.CurrentVolume = 1;
            }
        }

        var franchiseName = !string.IsNullOrWhiteSpace(request.FranchiseName)
            ? request.FranchiseName.Trim()
            : InferFranchiseName(item.Title);

        if (item.FranchiseId is null && !string.IsNullOrWhiteSpace(franchiseName))
        {
            var franchise = await db.Franchises.FirstOrDefaultAsync(f => f.Name.ToLower() == franchiseName.ToLower(), ct);
            if (franchise is not null)
            {
                item.FranchiseId = franchise.Id;
                item.Franchise = franchise;
            }
            else
            {
                var siblingExists = await db.MediaItems.AnyAsync(m => m.Title.ToLower() == franchiseName.ToLower() || (m.Franchise != null && m.Franchise.Name.ToLower() == franchiseName.ToLower()), ct);
                if (siblingExists || !string.IsNullOrWhiteSpace(request.FranchiseName))
                {
                    franchise = new Franchise { Id = Guid.NewGuid(), Name = franchiseName };
                    db.Franchises.Add(franchise);
                    item.FranchiseId = franchise.Id;
                    item.Franchise = franchise;

                    var siblingItem = await db.MediaItems.FirstOrDefaultAsync(m => m.FranchiseId == null && m.Title.ToLower() == franchiseName.ToLower(), ct);
                    if (siblingItem is not null)
                    {
                        siblingItem.FranchiseId = franchise.Id;
                    }
                }
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
            .Include(media => media.Franchise)
            .Include(media => ((TvShow)media).Seasons)
            .Include(media => ((Manga)media).Volumes)
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

        if (request.TranslatedSynopsis is not null)
        {
            item.TranslatedSynopsis = request.TranslatedSynopsis;
            item.TranslationLanguage = request.TranslationLanguage;
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

        if (request.FranchiseId is not null)
        {
            item.FranchiseId = request.FranchiseId;
        }
        else if (!string.IsNullOrWhiteSpace(request.FranchiseName))
        {
            var franchise = await db.Franchises.FirstOrDefaultAsync(f => f.Name.ToLower() == request.FranchiseName.Trim().ToLower(), ct);
            if (franchise is null)
            {
                franchise = new Franchise { Id = Guid.NewGuid(), Name = request.FranchiseName.Trim() };
                db.Franchises.Add(franchise);
            }
            item.FranchiseId = franchise.Id;
            item.Franchise = franchise;
        }

        if (request.FranchiseOrder is not null)
        {
            item.FranchiseOrder = request.FranchiseOrder;
        }

        if (item is Manga manga)
        {
            if (request.Author is not null) manga.Author = request.Author;
            if (request.RomajiTitle is not null) manga.RomajiTitle = request.RomajiTitle;
            if (request.TotalVolumes.HasValue) manga.TotalVolumes = request.TotalVolumes.Value;
            if (request.CurrentVolume.HasValue) manga.CurrentVolume = request.CurrentVolume.Value;
            if (request.TotalChapters.HasValue) manga.TotalChapters = request.TotalChapters.Value;
            if (request.CurrentChapter.HasValue) manga.CurrentChapter = request.CurrentChapter.Value;
        }
        else if (item is Book book)
        {
            if (request.Author is not null) book.Author = request.Author;
            if (request.TotalPages.HasValue) book.TotalPages = request.TotalPages.Value;
            if (request.CurrentPage.HasValue) book.CurrentPage = request.CurrentPage.Value;
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
            item.StartedAt ??= DateTime.UtcNow;

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
        var item = await db.MediaItems.SingleOrDefaultAsync(media => media.Id == id, ct);
        if (item is null)
        {
            return Results.NotFound();
        }

        if (item is TvShow tvShow)
        {
            await db.Entry(tvShow).Collection(s => s.Seasons).LoadAsync(ct);
        }

        var type = MediaResponseMapper.GetType(item);
        if (item is TvShow { IsAnime: true } or Movie { IsAnime: true })
        {
            type = "anime";
        }

        var external = await metadataAggregator.GetDetailsAsync(type, item.ExternalId ?? "", item.Title, ct, item.ExternalSource);
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
            item.ExternalRatingsJson = System.Text.Json.JsonSerializer.Serialize(
                external.Ratings,
                new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
        }

        if (!string.IsNullOrWhiteSpace(external.ReleaseDate) && DateTime.TryParse(external.ReleaseDate, out var parsedRelDate))
        {
            item.ReleaseDate = parsedRelDate;
        }
        else if (external.ReleaseYear is > 0 && item.ReleaseDate is null)
        {
            item.ReleaseDate = new DateTime(external.ReleaseYear.Value, 1, 1);
        }

        if (!string.IsNullOrWhiteSpace(external.EndDate) && DateTime.TryParse(external.EndDate, out var parsedEndDate))
        {
            item.EndDate = parsedEndDate;
        }

        item.ReleaseStatus = !string.IsNullOrWhiteSpace(external.ReleaseStatus)
            ? external.ReleaseStatus
            : ComputeReleaseStatusFromDates(item.ReleaseDate, item.EndDate);

        if (item is TvShow show)
        {
            if (external.RuntimeMinutes is > 0)
            {
                show.EpisodeDurationMinutes = external.RuntimeMinutes;
            }
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
            if (external.RuntimeMinutes is > 0) movie.DurationMinutes = external.RuntimeMinutes.Value;
            else if (external.TotalCount is > 0) movie.DurationMinutes = external.TotalCount.Value;
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
            if (external.Chapters is > 0) manga.TotalChapters = external.Chapters.Value;
            if (external.Volumes is > 0) manga.TotalVolumes = external.Volumes.Value;
            if (!string.IsNullOrWhiteSpace(external.Author)) manga.Author = external.Author;
            if (!string.IsNullOrWhiteSpace(external.RomajiTitle)) manga.RomajiTitle = external.RomajiTitle;
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
        if (show?.Seasons.Count > 0)
        {
            var totalWatched = show.Seasons.Sum(item => item.CurrentEpisode);
            var allCompleted = show.Seasons.All(item => item.Status == MediaStatus.Completed);

            if (allCompleted)
            {
                show.Status = MediaStatus.Completed;
                show.FinishedAt ??= DateTime.UtcNow;
                show.StartedAt ??= DateTime.UtcNow;
            }
            else if (totalWatched > 0)
            {
                if (show.Status == MediaStatus.Completed || show.Status == MediaStatus.Planned)
                {
                    show.Status = MediaStatus.InProgress;
                }
                show.FinishedAt = null;
                show.StartedAt ??= DateTime.UtcNow;
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

    private static async Task<IResult> UpdateVolumeProgress(
        Guid id,
        UpdateVolumeProgressRequest request,
        AppDbContext db,
        IValidator<UpdateVolumeProgressRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

        var volume = await db.MangaVolumes.Include(v => v.Manga).SingleOrDefaultAsync(item => item.Id == id, ct);
        if (volume is null)
        {
            return Results.NotFound();
        }

        if (request.CurrentPage.HasValue)
        {
            volume.CurrentPage = ClampToKnownTotal(Math.Max(request.CurrentPage.Value, 0), volume.TotalPages);
        }
        if (request.CurrentChapter.HasValue)
        {
            volume.CurrentChapter = ClampToKnownTotal(Math.Max(request.CurrentChapter.Value, 0), volume.TotalChapters);
        }

        if ((volume.TotalChapters > 0 && volume.CurrentChapter >= volume.TotalChapters) ||
            (volume.TotalPages > 0 && volume.CurrentPage >= volume.TotalPages))
        {
            volume.Status = MediaStatus.Completed;
        }
        else if (volume.CurrentPage > 0 || volume.CurrentChapter > 0)
        {
            volume.Status = MediaStatus.InProgress;
        }
        else
        {
            volume.Status = MediaStatus.Planned;
        }

        if (volume.Manga is not null)
        {
            volume.Manga.CurrentVolume = volume.VolumeNumber;
            if (request.CurrentChapter.HasValue)
            {
                volume.Manga.CurrentChapter = request.CurrentChapter.Value;
            }
        }

        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    private static async Task<IResult> AddVolume(
        CreateVolumeRequest request,
        Guid mangaId,
        AppDbContext db,
        CancellationToken ct)
    {
        var manga = await db.Manga.Include(m => m.Volumes).SingleOrDefaultAsync(m => m.Id == mangaId, ct);
        if (manga is null) return Results.NotFound();

        var volumeNumber = request.VolumeNumber > 0 ? request.VolumeNumber : manga.Volumes.Count + 1;
        var volume = new MangaVolume
        {
            MangaId = mangaId,
            VolumeNumber = volumeNumber,
            Title = string.IsNullOrWhiteSpace(request.Title) ? $"Volume {volumeNumber}" : request.Title,
            CoverUrl = request.CoverUrl,
            TotalPages = Math.Max(request.TotalPages, 0),
            CurrentPage = Math.Max(request.CurrentPage, 0),
            TotalChapters = Math.Max(request.TotalChapters, 0),
            CurrentChapter = Math.Max(request.CurrentChapter, 0),
            Status = request.Status,
            Score = request.Score,
            Notes = request.Notes,
            ReleaseDate = request.ReleaseDate,
        };

        db.MangaVolumes.Add(volume);
        await db.SaveChangesAsync(ct);
        return Results.Created($"/api/volumes/{volume.Id}", MediaResponseMapper.ToDto(volume));
    }

    private static async Task<IResult> UpdateVolume(
        Guid id,
        UpdateVolumeRequest request,
        AppDbContext db,
        CancellationToken ct)
    {
        var volume = await db.MangaVolumes.SingleOrDefaultAsync(v => v.Id == id, ct);
        if (volume is null) return Results.NotFound();

        if (request.Title is not null) volume.Title = request.Title;
        if (request.CoverUrl is not null) volume.CoverUrl = request.CoverUrl;
        if (request.TotalPages.HasValue) volume.TotalPages = Math.Max(request.TotalPages.Value, 0);
        if (request.CurrentPage.HasValue) volume.CurrentPage = Math.Max(request.CurrentPage.Value, 0);
        if (request.TotalChapters.HasValue) volume.TotalChapters = Math.Max(request.TotalChapters.Value, 0);
        if (request.CurrentChapter.HasValue) volume.CurrentChapter = Math.Max(request.CurrentChapter.Value, 0);
        if (request.Status.HasValue) volume.Status = request.Status.Value;
        if (request.Score.HasValue) volume.Score = request.Score.Value;
        if (request.Notes is not null) volume.Notes = request.Notes;

        await db.SaveChangesAsync(ct);
        return Results.Ok(MediaResponseMapper.ToDto(volume));
    }

    private static async Task<IResult> DeleteVolume(
        Guid id,
        AppDbContext db,
        CancellationToken ct)
    {
        var volume = await db.MangaVolumes.SingleOrDefaultAsync(v => v.Id == id, ct);
        if (volume is null) return Results.NotFound();

        db.MangaVolumes.Remove(volume);
        await db.SaveChangesAsync(ct);
        return Results.NoContent();
    }

    public static string? InferFranchiseName(string? title)
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

        var seasonRegex = new System.Text.RegularExpressions.Regex(
            @"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|[IVXLCDM]+)$",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        var match = seasonRegex.Replace(clean, "").Trim();
        if (match.Length >= 3 && match != clean)
        {
            return match;
        }

        return null;
    }

    public static async Task AutoBackfillFranchisesAsync(AppDbContext db)
    {
        var unlinked = await db.MediaItems.Where(m => m.FranchiseId == null).ToListAsync();
        if (unlinked.Count == 0) return;

        var groups = unlinked
            .Select(m => new { Item = m, FranchiseName = InferFranchiseName(m.Title) })
            .Where(x => !string.IsNullOrWhiteSpace(x.FranchiseName))
            .GroupBy(x => x.FranchiseName!.ToLowerInvariant())
            .ToList();

        foreach (var grp in groups)
        {
            var inferredName = grp.First().FranchiseName!;
            var existingFranchise = await db.Franchises.FirstOrDefaultAsync(f => f.Name.ToLower() == grp.Key);
            var exactMatchItem = unlinked.FirstOrDefault(m => m.Title.Equals(inferredName, StringComparison.OrdinalIgnoreCase));

            if (existingFranchise is not null || grp.Count() > 1 || exactMatchItem is not null)
            {
                if (existingFranchise is null)
                {
                    existingFranchise = new Franchise { Id = Guid.NewGuid(), Name = inferredName };
                    db.Franchises.Add(existingFranchise);
                }

                foreach (var x in grp)
                {
                    x.Item.FranchiseId = existingFranchise.Id;
                }
                if (exactMatchItem is not null && exactMatchItem.FranchiseId == null)
                {
                    exactMatchItem.FranchiseId = existingFranchise.Id;
                }
            }
        }

        await db.SaveChangesAsync();
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
                Author = request.Author,
                RomajiTitle = request.RomajiTitle,
                TotalVolumes = request.TotalVolumes,
                TotalChapters = request.TotalChapters,
                CurrentVolume = request.CurrentVolume ?? 0,
                Volumes = request.Volumes?
                    .Select(volume => new MangaVolume
                    {
                        VolumeNumber = volume.VolumeNumber,
                        Title = volume.Title,
                        CoverUrl = volume.CoverUrl,
                        TotalPages = volume.TotalPages,
                        CurrentPage = volume.CurrentPage,
                        TotalChapters = volume.TotalChapters,
                        CurrentChapter = volume.CurrentChapter,
                        Status = volume.Status,
                        Score = volume.Score,
                        Notes = volume.Notes,
                        ReleaseDate = volume.ReleaseDate,
                    })
                    .ToList() ?? [],
                Title = request.Title,
            },
            "movie" => new Movie
            {
                DurationMinutes = request.DurationMinutes ?? 0,
                Director = request.Director,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                RomajiTitle = request.RomajiTitle,
                Title = request.Title,
            },
            "tvshow" => new TvShow
            {
                Network = request.Network,
                IsAnime = request.IsAnime ?? false,
                Studio = request.Studio,
                RomajiTitle = request.RomajiTitle,
                EpisodeDurationMinutes = request.EpisodeDurationMinutes ?? request.DurationMinutes,
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
        item.ReleaseDate = request.ReleaseDate;
        item.EndDate = request.EndDate;
        item.ReleaseStatus = !string.IsNullOrWhiteSpace(request.ReleaseStatus)
            ? request.ReleaseStatus
            : ComputeReleaseStatusFromDates(request.ReleaseDate, request.EndDate);

        return item;
    }

    private static int ClampToKnownTotal(int current, int? total) =>
        total is > 0 ? Math.Min(current, total.Value) : current;

    private static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));

    private static string? ComputeReleaseStatusFromDates(DateTime? releaseDate, DateTime? endDate)
    {
        var now = DateTime.UtcNow.Date;
        if (endDate is { } end && end <= now)
        {
            return "FINISHED";
        }
        if (releaseDate is { } start)
        {
            if (start > now)
            {
                return "NOT_YET_RELEASED";
            }
            return "RELEASING";
        }
        return null;
    }

    private sealed class UnsupportedMediaTypeException(string mediaType)
        : InvalidOperationException($"Unsupported media type '{mediaType}'.");
}
