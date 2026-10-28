using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;
using System.Globalization;

namespace MediaTracker.Server.Features.Media.UpdateMedia;

public sealed record UpdateMediaCommand(Guid Id, UpdateMediaRequest Request);

public interface IUpdateMediaHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(UpdateMediaCommand command, CancellationToken ct);
}

public sealed class UpdateMediaHandler(
    AppDbContext db,
    IValidator<UpdateMediaRequest> validator,
    IFranchiseService franchiseService,
    IMemoryCache cache) : IUpdateMediaHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(UpdateMediaCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var validation = await validator.ValidateAsync(request, ct);
        if (validation.ToError() is { } validationError)
        {
            return Result<MediaDetailDto>.Failure(validationError);
        }

        var item = await db.LoadMediaItemAsync(command.Id, ct);

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{command.Id}' was not found."));
        }

        var previousStatus = item.Status;
        var previousScore = item.Score;
        var previousAchievements = item.UnlockedAchievements;
        var previousProgress = GetProgressValue(item);

        MediaItemUpdater.Apply(item, request);
        await franchiseService.LinkFranchiseOnUpdateAsync(db, item, request.FranchiseId, request.FranchiseName, ct);

        var events = new List<MediaEvent>();
        RecordEvents(item, previousStatus, previousScore, previousAchievements, previousProgress, events, command.Id);

        var currentProgress = GetProgressValue(item);
        if (request.LastActivityAt is null && (item.Status != previousStatus || item.Score != previousScore || currentProgress != previousProgress))
        {
            item.LastActivityAt = DateTime.UtcNow;
        }

        item.MarkUpdated();

        await db.UpdateMediaItemAsync(item, ct);

        // Insert events recorded during the update.
        foreach (var evt in events)
        {
            await db.InsertMediaEventAsync(evt, ct);
        }

        // Persist season/volume changes.
        if (item is TvShow show)
        {
            foreach (var season in show.Seasons)
            {
                await db.InsertTvSeasonAsync(season, ct);
            }
        }
        if (item is Manga manga)
        {
            foreach (var volume in manga.Volumes)
            {
                await db.InsertMangaVolumeAsync(volume, ct);
            }
        }

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    private static void RecordEvents(
        MediaItem item,
        MediaStatus previousStatus,
        int? previousScore,
        string? previousAchievements,
        string? previousProgress,
        List<MediaEvent> events,
        Guid mediaId)
    {
        if (item.Status != previousStatus)
        {
            events.Add(MediaEventRecorder.StatusChanged(item, previousStatus, item.Status));
        }

        if (item.Score != previousScore)
        {
            events.Add(MediaEventRecorder.ScoreChanged(item, previousScore, item.Score));
        }

        var currentProgress = GetProgressValue(item);
        if (currentProgress != previousProgress)
        {
            events.Add(MediaEventRecorder.ProgressChanged(item, previousProgress, currentProgress));
        }

        foreach (var name in MediaAchievements.NewlyUnlocked(previousAchievements, item.UnlockedAchievements))
        {
            events.Add(MediaEventRecorder.AchievementUnlocked(item, name));
        }
    }

    private static string? GetProgressValue(MediaItem item) => item switch
    {
        VideoGame game => game.HoursPlayed?.ToString(CultureInfo.InvariantCulture),
        Book book => book.CurrentPage.ToString(CultureInfo.InvariantCulture),
        Manga manga => $"{manga.CurrentChapter}:{manga.CurrentVolume}",
        TvShow show => show.TotalEpisodesWatched.ToString(CultureInfo.InvariantCulture),
        _ => null,
    };
}
