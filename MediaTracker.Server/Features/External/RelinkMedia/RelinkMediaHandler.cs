using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Media.GetMediaDetail;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.External.RelinkMedia;

public sealed record RelinkMediaRequest(string ExternalId, string Source, string Type, string? Title = null);

public sealed record RelinkMediaCommand(Guid MediaId, RelinkMediaRequest Request);

public interface IRelinkMediaHandler
{
    Task<Result<MediaDetailDto>> HandleAsync(RelinkMediaCommand command, CancellationToken ct);
}

/// <summary>
/// Re-points an existing item at another provider: "this is the same show, but on TMDb instead of
/// Kinopoisk". Refresh cannot do this — it re-reads the id the row already stores, which is the very
/// thing that matched wrong. Everything the new source reports overwrites the stored metadata, and the
/// cached related list is dropped because it was fetched for the previous entity.
/// </summary>
public sealed class RelinkMediaHandler(
    AppDbContext db,
    MetadataAggregatorService aggregator,
    IImageStorageService imageStorage) : IRelinkMediaHandler
{
    public async Task<Result<MediaDetailDto>> HandleAsync(RelinkMediaCommand command, CancellationToken ct)
    {
        var request = command.Request;

        if (string.IsNullOrWhiteSpace(request.ExternalId)
            || string.IsNullOrWhiteSpace(request.Source)
            || string.IsNullOrWhiteSpace(request.Type))
        {
            return Result<MediaDetailDto>.Failure(
                Error.Validation("externalId, source and type are all required."));
        }

        var item = await MediaItemGraph
            .LoadTracked(db)
            .SingleOrDefaultAsync(media => media.Id == command.MediaId, ct);

        if (item is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"Media item '{command.MediaId}' was not found."));
        }

        // The external id only means something to the named source, so it is a hard request: the
        // aggregator resolves that provider alone and never substitutes another one. The caller's
        // title wins over the stored one: a translated row ("Северная правда") is useless as a
        // lookup key, so the original title the user matched on has to reach the provider.
        var lookupTitle = string.IsNullOrWhiteSpace(request.Title)
            ? item.Title
            : request.Title;

        var external = await aggregator.GetDetailsAsync(
            request.Type,
            request.ExternalId.Trim(),
            lookupTitle,
            ct,
            request.Source);

        if (external is null)
        {
            return Result<MediaDetailDto>.Failure(
                Error.NotFound($"'{request.Source}' has no record for '{request.ExternalId}'."));
        }

        await MediaMetadataApplier.ApplyOverwriteAsync(
            item,
            external,
            imageStorage,
            ct,
            season => db.Entry(season).State = EntityState.Added,
            volume => db.Entry(volume).State = EntityState.Added);

        // The cached relations were fetched through the old provider for a different entity id.
        item.RelatedMediaJson = null;
        item.RelatedSource = null;

        item.MarkUpdated();
        await db.SaveChangesAsync(ct);

        return Result<MediaDetailDto>.Success(MediaDetailProjection.ToDetailDto(item));
    }
}