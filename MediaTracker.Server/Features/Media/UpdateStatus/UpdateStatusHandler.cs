using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.UpdateStatus;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.UpdateStatus;

public sealed record UpdateStatusCommand(Guid Id, MediaStatus Status);

public interface IUpdateStatusHandler
{
    Task<Result> HandleAsync(UpdateStatusCommand command, CancellationToken ct);
}

public sealed class UpdateStatusHandler(
    AppDbContext db,
    IValidator<UpdateStatusRequest> validator) : IUpdateStatusHandler
{
    public async Task<Result> HandleAsync(UpdateStatusCommand command, CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(new UpdateStatusRequest { Status = command.Status }, ct);
        if (validation.ToError() is { } validationError)
        {
            return Result.Failure(validationError);
        }

        var item = await MediaItemGraph
            .LoadTracked(db)
            .SingleOrDefaultAsync(media => media.Id == command.Id, ct);

        if (item is null)
        {
            return Result.Failure(Error.NotFound($"Media item '{command.Id}' was not found."));
        }

        var previousStatus = item.Status;

        // The entity owns the transition: it sets the timestamps, rewrites the type-specific counters
        // and completes or resets the show's seasons.
        item.ChangeStatus(command.Status);
        item.MarkUpdated();

        if (item.Status != previousStatus)
        {
            db.Events.Add(MediaEventRecorder.StatusChanged(item, previousStatus, item.Status));
        }

        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
