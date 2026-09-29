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
    private static readonly System.Text.Json.JsonSerializerOptions CamelCaseJsonOptions = new()
    {
        PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
    };

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
        var normalizedType = type?.Trim().ToLowerInvariant();
        var includeSeasons = string.IsNullOrWhiteSpace(normalizedType) || normalizedType is "tvshow" or "anime";
        var includeVolumes = string.IsNullOrWhiteSpace(normalizedType) || normalizedType is "manga";

        IQueryable<MediaItem> query = db.MediaItems
            .AsNoTracking()
            .Include(media => media.Franchise);

        if (includeSeasons)
        {
            query = query.Include(media => ((TvShow)media).Seasons);
        }

        if (includeVolumes)
        {
            query = query.Include(media => ((Manga)media).Volumes);
        }

        if (!string.IsNullOrWhiteSpace(normalizedType))
        {
            var discriminator = normalizedType switch
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
                || (EF.Property<string>(item, Discriminator) == "Movie" && ((Movie)item).RomajiTitle != null && EF.Functions.Like(((Movie)item).RomajiTitle, $"%{term}%"))
                || (EF.Property<string>(item, Discriminator) == "TvShow" && ((TvShow)item).RomajiTitle != null && EF.Functions.Like(((TvShow)item).RomajiTitle, $"%{term}%")));
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
        var counts = await db.MediaItems
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
            })
            .FirstOrDefaultAsync(ct);

        var stats = new MediaStatsDto
        {
            TotalItems = counts?.Total ?? 0,
            CompletedItems = counts?.Completed ?? 0,
            InProgressItems = counts?.InProgress ?? 0,
            PlannedItems = counts?.Planned ?? 0,
            CompletedGamesCount = counts?.CompletedGames ?? 0,
            CompletedBooksCount = counts?.CompletedBooks ?? 0,
            CompletedMoviesCount = counts?.CompletedMovies ?? 0,
            TotalHoursPlayed = await db.Games.SumAsync(game => game.HoursPlayed ?? 0, ct),
            TotalPagesRead = await db.Books.SumAsync(book => book.CurrentPage, ct),
            TotalChaptersRead = await db.Manga.SumAsync(manga => manga.CurrentChapter, ct),
            TotalEpisodesWatched = await db.TvSeasons.SumAsync(season => season.CurrentEpisode, ct),
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
                var modified = false;

                if (enriched.Ratings is { Count: > 0 } ratings)
                {
                    item.ExternalRatingsJson = System.Text.Json.JsonSerializer.Serialize(
                        ratings.Select(r => new { source = r.Source, score = r.Rating, votes = r.Votes }));
                    if (enriched.Rating > 0)
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

                if (string.IsNullOrWhiteSpace(item.Genres) && enriched.Genres is { Count: > 0 })
                {
                    item.Genres = string.Join(", ", enriched.Genres);
                    modified = true;
                }

                if (string.IsNullOrWhiteSpace(item.ReleaseStatus) && !string.IsNullOrWhiteSpace(enriched.ReleaseStatus))
                {
                    item.ReleaseStatus = enriched.ReleaseStatus;
                    modified = true;
                }

                if (modified)
                {
                    item.UpdatedAt = DateTime.UtcNow;
                    await db.SaveChangesAsync(ct);
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // Fallback gracefully on metadata enrichment failure
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

        if (request.Genres is not null)
        {
            item.Genres = request.Genres;
        }

        if (request.Tags is not null)
        {
            item.Tags = request.Tags;
        }

        if (request.UnlockedAchievements is not null)
        {
            item.UnlockedAchievements = request.UnlockedAchievements;
        }

        if (request.UserPlatform is not null)
        {
            item.UserPlatform = request.UserPlatform;
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

        await franchiseService.LinkFranchiseOnUpdateAsync(db, item, request.FranchiseId, request.FranchiseName, ct);

        if (request.FranchiseOrder is not null)
        {
            item.FranchiseOrder = request.FranchiseOrder;
        }

        if (item is VideoGame game)
        {
            if (request.Platform is not null) game.Platform = request.Platform;
            if (request.UserPlatform is not null) game.UserPlatform = request.UserPlatform;
        }
        else if (item is Book book)
        {
            if (request.Author is not null) book.Author = request.Author;
            if (request.TotalPages.HasValue) book.TotalPages = request.TotalPages.Value;
            if (request.CurrentPage.HasValue) book.CurrentPage = request.CurrentPage.Value;
        }
        else if (item is Manga manga)
        {
            if (request.Author is not null) manga.Author = request.Author;
            if (request.RomajiTitle is not null) manga.RomajiTitle = request.RomajiTitle;
            if (request.TotalVolumes.HasValue) manga.TotalVolumes = request.TotalVolumes;
            if (request.CurrentVolume.HasValue) manga.CurrentVolume = request.CurrentVolume.Value;
            if (request.TotalChapters.HasValue) manga.TotalChapters = request.TotalChapters;
            if (request.CurrentChapter.HasValue) manga.CurrentChapter = request.CurrentChapter.Value;
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
        else if (request.Status == MediaStatus.InProgress)
        {
            item.StartedAt ??= DateTime.UtcNow;
            item.FinishedAt = null;
        }
        else if (request.Status == MediaStatus.Planned)
        {
            item.FinishedAt = null;
            item.StartedAt = null;
        }
        else if (request.Status == MediaStatus.OnHold)
        {
            item.FinishedAt = null;
        }
        else if (request.Status == MediaStatus.Dropped)
        {
            item.FinishedAt ??= DateTime.UtcNow;
        }

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

        var normalized = kind.Trim().ToLowerInvariant();
        if (normalized == "started")
        {
            item.StartedAt = null;
        }
        else if (normalized == "finished")
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
                CamelCaseJsonOptions);
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
            : MediaItemFactory.ComputeReleaseStatusFromDates(item.ReleaseDate, item.EndDate);

        if (external.Genres is { Count: > 0 })
        {
            item.Genres = string.Join(", ", external.Genres);
        }

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

    private static int ClampToKnownTotal(int current, int? total) =>
        total is > 0 ? Math.Min(current, total.Value) : current;

    private static bool IsExternalUrl(string? url) =>
        url is not null &&
        (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
         url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));
}
