using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.MediaContract;
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
    IFranchiseService franchiseService) : ICreateMediaHandler
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

        if (MediaMetadataApplier.IsExternalUrl(item.CoverUrl))
        {
            item.CoverUrl = await imageStorage.SaveCoverAsync(item.CoverUrl!, item.Id, ct);
        }

        MediaCollectionSeeder.SeedPlaceholderSeasons(item, request);
        MediaCollectionSeeder.SeedPlaceholderVolumes(item, request);

        await franchiseService.LinkFranchiseOnCreateAsync(db, item, request.FranchiseName, ct);

        db.Add(item);
        db.Events.Add(MediaEventRecorder.Added(item));
        await db.SaveChangesAsync(ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}
