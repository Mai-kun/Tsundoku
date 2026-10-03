using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.Media.CreateMedia;

public sealed record CreateMediaCommand(CreateMediaRequest Request);

public interface ICreateMediaHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(CreateMediaCommand command, CancellationToken ct);
}

public sealed class CreateMediaHandler(
    AppDbContext db,
    IValidator<CreateMediaRequest> validator,
    IImageStorageService imageStorage,
    IFranchiseService franchiseService,
    IJobManager jobs) : ICreateMediaHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(CreateMediaCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var validation = await validator.ValidateAsync(request, ct);
        if (validation.ToError() is { } validationError)
        {
            return Result<MediaDetailDto>.Failure(validationError);
        }

        var item = MediaItemFactory.CreateEntity(request);

        // Coming from search, the payload already carries everything the card needs to render, so
        // the heavy provider work moves to the queue instead of holding the request open.
        var deferEnrichment = IsFromSearch(item);

        if (deferEnrichment)
        {
            item.SyncStatus = SyncStatus.Syncing;
        }
        else if (MediaMetadataApplier.IsExternalUrl(item.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(item.CoverUrl!, item.Id, ct);
        }

        MediaCollectionSeeder.SeedPlaceholderSeasons(item, request);
        MediaCollectionSeeder.SeedPlaceholderVolumes(item, request);

        await franchiseService.LinkFranchiseOnCreateAsync(db, item, request.FranchiseName, ct);

        db.Add(item);
        db.Events.Add(MediaEventRecorder.Added(item));
        await db.SaveChangesAsync(ct);

        if (deferEnrichment)
        {
            jobs.Enqueue(
                item.Id,
                item.Title,
                (sp, token, progress) => MediaEnrichmentJob.RunAsync(sp, item.Id, token, progress));
        }

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }

    /// <summary>
    /// Only search hits are worth a background pass: a hand-written entry has no external id for the
    /// aggregator to resolve, so queueing it would just burn a job that finds nothing.
    /// </summary>
    private static bool IsFromSearch(MediaItem item) =>
        !string.IsNullOrWhiteSpace(item.ExternalId);
}
