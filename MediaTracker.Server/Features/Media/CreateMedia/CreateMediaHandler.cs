using System.Text.Json;
using FluentValidation;
using MediaTracker.Server.Common.Http;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Common;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.CreateMedia;
using MediaTracker.Server.Features.Media.GetMediaList;
using MediaTracker.Server.Features.Media.GetMediaStats;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Features.Media.PendingMatches;
using MediaTracker.Server.Infrastructure.Jobs;
using MediaTracker.Server.Infrastructure.Persistence.Franchises;
using MediaTracker.Server.Infrastructure.Persistence;
using MediaTracker.Server.Infrastructure.Storage;
using Microsoft.Extensions.Caching.Memory;

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
    IJobManager jobs,
    IMemoryCache cache) : ICreateMediaHandler
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

        // Duplicate guard: the same title often arrives from a second provider under another name
        // ("Noragami" from AniList against Shikimori's "Бездомный бог"). The row is still created,
        // but parked in review with a conflict marker instead of enriching into a clone card.
        var duplicate = await CheckForDuplicateAsync(item, ct);

        // Coming from search, the payload already carries everything the card needs to render, so
        // the heavy provider work moves to the queue instead of holding the request open.
        var deferEnrichment = IsFromSearch(item) && duplicate is null;

        if (duplicate is not null)
        {
            item.SyncStatus = SyncStatus.NeedsReview;
            item.PendingMatchesJson = JsonSerializer.Serialize(
                duplicate,
                AppJsonSerializerContext.Default.DuplicateConflictDto);
        }

        if (deferEnrichment)
        {
            item.SyncStatus = SyncStatus.Syncing;
        }
        else if (MediaMetadataApplier.IsExternalUrl(item.CoverUrl))
        {
            // A hand-created row starts its gallery right away: the first cover is variant #1, so
            // later refreshes add to it instead of replacing the only poster the row has.
            var variant = await imageStorage.SaveCoverVariantAsync(item.CoverUrl!, item.Id, item.ExternalSource, ct);
            if (variant is not null)
            {
                item.CoversJson = MediaCoverCollection.Serialize([variant]);
                item.CoverUrl = variant.ThumbUrl;
            }
            else
            {
                item.CoverUrl = await imageStorage.SaveCoverAsync(item.CoverUrl!, item.Id, ct);
            }
        }

        MediaCollectionSeeder.SeedPlaceholderSeasons(item, request);

        await franchiseService.LinkFranchiseOnCreateAsync(db, item, request.FranchiseName, ct);

        item.LastActivityAt = DateTime.UtcNow;

        await db.InsertMediaItemAsync(item, ct);
        await db.InsertMediaEventAsync(MediaEventRecorder.Added(item), ct);

        // Persist placeholder seasons created by the seeder.
        if (item is TvShow show)
        {
            foreach (var season in show.Seasons)
            {
                await db.InsertTvSeasonAsync(season, ct);
            }
        }

        AdvancedStatsCalculator.InvalidateCache(cache);
        TasteProfileCalculator.InvalidateCache(cache);
        MediaListCache.Invalidate();

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

    /// <summary>
    /// Looks for a library row the title being added is a duplicate of. For the same media type
    /// three checks combine: a name match across languages (the cross-language bridge lets
    /// AniList's "Noragami" hit Shikimori's "Бездомный бог" through a synonym), an equal season /
    /// part marker (no marker on both sides means both are first seasons) and no contradiction in
    /// the release years (delta over one year) or the episode / chapter counts — unknown values
    /// never veto, contradicting ones always do.
    /// </summary>
    private async Task<DuplicateConflictDto?> CheckForDuplicateAsync(MediaItem item, CancellationToken ct)
    {
        var incomingNames = TitleVariants(item, includeAltTitles: false);
        if (incomingNames.Count == 0)
        {
            return null;
        }

        var incomingRoots = BaseRoots(incomingNames);
        var existing = await db.LoadMediaItemsAsync(MediaTypeKey(item), null, null, null, null, null, ct);

        foreach (var candidate in existing)
        {
            if (candidate.Id == item.Id) continue;

            var candidateNames = TitleVariants(candidate, includeAltTitles: true);
            if (candidateNames.Count == 0) continue;

            if (!NamesMatch(incomingNames, incomingRoots, candidateNames)) continue;
            if (!StrictCoverMatcher.SeasonMarkersMatch(item, candidate)) continue;

            // Corroborating evidence, not a hard requirement: an incoming payload with no year and
            // no count yet (the placeholder seasons are not seeded at this point) must still be
            // caught, so the gate only vetoes on CONTRADICTING data — which is exactly what
            // separates a duplicate from a same-name sequel of another season or year.
            var yearsContradict = item.ReleaseYear is > 0
                && candidate.ReleaseYear is > 0
                && Math.Abs(item.ReleaseYear.Value - candidate.ReleaseYear.Value) > 1;
            var countsContradict = CountOf(item) is { } leftCount
                && CountOf(candidate) is { } rightCount
                && leftCount != rightCount;
            if (yearsContradict || countsContradict) continue;

            return new DuplicateConflictDto(
                ConflictType: "duplicate",
                ExistingMediaId: candidate.Id,
                ExistingTitle: candidate.Title,
                IncomingSource: item.ExternalSource,
                IncomingExternalId: item.ExternalId,
                IncomingTitle: item.Title);
        }

        return null;
    }

    /// <summary>Title plus romaji and original — the variants the create payload itself carries.</summary>
    private static List<string> TitleVariants(MediaItem item, bool includeAltTitles)
    {
        string? romaji = item switch
        {
            Manga manga => manga.RomajiTitle,
            Movie movie => movie.RomajiTitle,
            TvShow show => show.RomajiTitle,
            _ => null,
        };

        var names = new List<string>();
        foreach (var name in new[] { item.Title, romaji, item.OriginalTitle })
        {
            if (!string.IsNullOrWhiteSpace(name)) names.Add(name.Trim());
        }

        if (includeAltTitles)
        {
            names.AddRange(MediaMetadataApplier
                .DeserializeAltTitles(item.AltTitles)
                .Where(name => !string.IsNullOrWhiteSpace(name))
                .Select(name => name.Trim()));
        }

        return names;
    }

    /// <summary>
    /// Exact hit in any language wins; a shared stripped base ("Noragami: Stray God" roots to
    /// "noragami") is accepted too — the season and year/count gates weed out sequels.
    /// </summary>
    private bool NamesMatch(List<string> incoming, HashSet<string> incomingRoots, List<string> candidateNames)
    {
        var candidateKeys = candidateNames
            .Select(FranchiseService.NormalizeKey)
            .Where(key => key.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
        if (incoming.Any(name => candidateKeys.Contains(FranchiseService.NormalizeKey(name))))
        {
            return true;
        }

        if (incomingRoots.Count == 0)
        {
            return false;
        }

        return BaseRoots(candidateNames).Any(incomingRoots.Contains);
    }

    private HashSet<string> BaseRoots(List<string> names) => names
        .Select(name => franchiseService.ExtractBaseTitle(name))
        .Where(root => root is { Length: > 4 })
        .Select(root => root!)
        .ToHashSet(StringComparer.Ordinal);

    /// <summary>The stored media type string as the list query expects it (case-insensitive anyway).</summary>
    private static string MediaTypeKey(MediaItem item) => item switch
    {
        TvShow => "TvShow",
        Movie => "Movie",
        Manga => "Manga",
        Book => "Book",
        VideoGame => "Game",
        _ => string.Empty,
    };

    private static int? CountOf(MediaItem item) => item switch
    {
        Manga manga => manga.TotalChapters is > 0 ? manga.TotalChapters : null,
        Book book => book.TotalChapters is > 0 ? book.TotalChapters : book.TotalPages > 0 ? book.TotalPages : null,
        TvShow show => show.Seasons is { Count: > 0 } ? show.Seasons.Sum(season => season.TotalEpisodes) : null,
        _ => null,
    };
}
