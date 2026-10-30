using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.Extensions.Caching.Memory;

namespace MediaTracker.Server.Features.Media.UpdateStatus;

public sealed record UpdateStatusCommand(Guid Id, MediaStatus Status, string? DropReason = null, string? DropNotes = null);

public interface IUpdateStatusHandler
{
    Task<Result> HandleAsync(UpdateStatusCommand command, CancellationToken ct);
}

public sealed class UpdateStatusHandler(
    AppDbContext db,
    IValidator<UpdateStatusRequest> validator,
    IMemoryCache cache) : IUpdateStatusHandler
{
    public async Task<Result> HandleAsync(UpdateStatusCommand command, CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(
            new UpdateStatusRequest
            {
                Status = command.Status,
                DropReason = command.DropReason,
                DropNotes = command.DropNotes,
            },
            ct);
        if (validation.ToError() is { } validationError)
        {
            return Result.Failure(validationError);
        }

        var item = await db.LoadMediaItemAsync(command.Id, ct);

        if (item is null)
        {
            return Result.Failure(Error.NotFound($"Media item '{command.Id}' was not found."));
        }

        var previousStatus = item.Status;

        // The entity owns the transition: it sets the timestamps, rewrites the type-specific counters
        // and completes or resets the show's seasons.
        item.ChangeStatus(command.Status);

        if (command.Status == MediaStatus.Dropped)
        {
            if (previousStatus != MediaStatus.Dropped || command.DropReason is not null)
            {
                item.DropReason = string.IsNullOrWhiteSpace(command.DropReason) ? null : command.DropReason;
            }

            if (previousStatus != MediaStatus.Dropped || command.DropNotes is not null)
            {
                item.DropNotes = string.IsNullOrWhiteSpace(command.DropNotes) ? null : command.DropNotes;
            }
        }
        else
        {
            item.DropReason = null;
            item.DropNotes = null;
        }

        item.MarkUpdated();

        var events = new List<MediaEvent>();
        if (item.Status != previousStatus)
        {
            item.LastActivityAt = DateTime.UtcNow;
            events.Add(MediaEventRecorder.StatusChanged(item, previousStatus, item.Status));
        }

        await db.UpdateMediaItemAsync(item, ct);

        foreach (var evt in events)
        {
            await db.InsertMediaEventAsync(evt, ct);
        }

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
        MediaListCache.Invalidate();
        return Result.Success();
    }
}
