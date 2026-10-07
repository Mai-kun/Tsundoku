using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.UpdateMedia;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

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

        var item = await MediaItemGraph
            .LoadTracked(db)
            .SingleOrDefaultAsync(media => media.Id == command.Id, ct);

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(Error.NotFound($"Media item '{command.Id}' was not found."));
        }

        var previousStatus = item.Status;
        var previousScore = item.Score;
        var previousAchievements = item.UnlockedAchievements;

        MediaItemUpdater.Apply(item, request);
        await franchiseService.LinkFranchiseOnUpdateAsync(db, item, request.FranchiseId, request.FranchiseName, ct);

        RecordEvents(item, previousStatus, previousScore, previousAchievements, db);

        item.MarkUpdated();
        await db.SaveChangesAsync(ct);
        cache.Remove(AdvancedStatsCalculator.CacheKey);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    private static void RecordEvents(
        MediaItem item,
        MediaStatus previousStatus,
        int? previousScore,
        string? previousAchievements,
        AppDbContext db)
    {
        if (item.Status != previousStatus)
        {
            db.Events.Add(MediaEventRecorder.StatusChanged(item, previousStatus, item.Status));
        }

        if (item.Score != previousScore)
        {
            db.Events.Add(MediaEventRecorder.ScoreChanged(item, previousScore, item.Score));
        }

        foreach (var name in MediaAchievements.NewlyUnlocked(previousAchievements, item.UnlockedAchievements))
        {
            db.Events.Add(MediaEventRecorder.AchievementUnlocked(item, name));
        }
    }
}
