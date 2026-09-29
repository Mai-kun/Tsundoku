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

        var volume = await db.MangaVolumes.Include(v => v.Manga).SingleOrDefaultAsync(item => item.Id == id, ct);
        if (volume is null)
        {
            return Results.NotFound();
        }

        if (request.CurrentPage.HasValue)
        {
            var page = Math.Max(request.CurrentPage.Value, 0);
            volume.CurrentPage = volume.TotalPages > 0 ? Math.Min(page, volume.TotalPages) : page;
        }

        if (request.CurrentChapter.HasValue)
        {
            var chapter = Math.Max(request.CurrentChapter.Value, 0);
            volume.CurrentChapter = volume.TotalChapters > 0 ? Math.Min(chapter, volume.TotalChapters) : chapter;
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
