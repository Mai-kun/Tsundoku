using FluentValidation;
using MediaTracker.Server.Data;
using MediaTracker.Server.DTOs;
using MediaTracker.Server.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Endpoints;

public static class VolumeEndpoints
{
    public static IEndpointRouteBuilder MapVolumeEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/volumes");

        group.MapPut("/{id:guid}/progress", UpdateVolumeProgress);
        group.MapPost("/", AddVolume);
        group.MapPut("/{id:guid}", UpdateVolume);
        group.MapDelete("/{id:guid}", DeleteVolume);

        return app;
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

        // Stepper hot path: project the four scalars the decision needs and UPDATE directly, instead of
        // tracking the volume plus its parent manga and flushing the whole graph through SaveChanges.
        var volume = await db.MangaVolumes
            .AsNoTracking()
            .Where(item => item.Id == id)
            .Select(item => new
            {
                item.TotalPages,
                item.TotalChapters,
                item.MangaId,
                item.VolumeNumber,
                item.CurrentPage,
                item.CurrentChapter,
            })
            .FirstOrDefaultAsync(ct);

        if (volume is null)
        {
            return Results.NotFound();
        }

        var currentPage = request.CurrentPage is { } requestedPage
            ? ProgressStepperRules.Clamp(requestedPage, volume.TotalPages)
            : (int?)null;

        var currentChapter = request.CurrentChapter is { } requestedChapter
            ? ProgressStepperRules.Clamp(requestedChapter, volume.TotalChapters)
            : (int?)null;

        var nextPage = currentPage ?? volume.CurrentPage;
        var nextChapter = currentChapter ?? volume.CurrentChapter;

        // nextPage/nextChapter fall back to the stored value, so writing both is a no-op for the
        // counter the caller did not touch and keeps the whole stepper write to a single UPDATE.
        var newStatus = ProgressStepperRules.ResolveVolumeStatus(
            nextPage, volume.TotalPages, nextChapter, volume.TotalChapters);

        await db.MangaVolumes
            .Where(item => item.Id == id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(item => item.CurrentPage, nextPage)
                .SetProperty(item => item.CurrentChapter, nextChapter)
                .SetProperty(item => item.Status, newStatus), ct);

        if (volume.MangaId != Guid.Empty)
        {
            await db.Manga
                .Where(item => item.Id == volume.MangaId)
                .ExecuteUpdateAsync(
                    s => (currentChapter is { } chapter
                        ? s.SetProperty(item => item.CurrentChapter, chapter)
                        : s)
                    .SetProperty(item => item.CurrentVolume, volume.VolumeNumber),
                    ct);
        }

        return Results.NoContent();
    }

    private static async Task<IResult> AddVolume(
        CreateVolumeRequest request,
        Guid mangaId,
        AppDbContext db,
        IValidator<CreateVolumeRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

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
        IValidator<UpdateVolumeRequest> validator,
        CancellationToken ct)
    {
        var validationResult = await validator.ValidateAsync(request, ct);
        if (!validationResult.IsValid)
        {
            return Results.ValidationProblem(validationResult.ToDictionary());
        }

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
}
