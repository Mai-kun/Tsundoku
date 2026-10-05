using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace MediaTracker.Server.Features.External;

/// <summary>
/// MangaDex is the one source of truth for a series' volume structure, no matter which provider the
/// row was originally added from. Shikimori and AniList both report a flat chapter count and nothing
/// else, so a title matched there used to get its volumes divided evenly by a local guess; asking
/// MangaDex by name returns the real per-volume chapter counts instead.
///
/// Lives here rather than inside a handler because three paths need it — background enrichment,
/// "enrich" and "refresh" — and each of them used to answer this question differently.
/// </summary>
public static class MangaVolumeStructure
{
    /// <summary>
    /// Fills the series' real volumes from <c>/manga/{id}/aggregate</c>.
    /// Returns true when the item changed and the caller should save.
    /// </summary>
    /// <param name="volumeDetailsFromSource">
    /// What the provider that answered the request already reported. When it carries a breakdown
    /// there is nothing left to ask MangaDex for, and a second round trip is wasted.
    /// </param>
    public static async Task<bool> ApplyCanonicalVolumesAsync(
        IMetadataProviderResolver providerResolver,
        AppDbContext db,
        Manga manga,
        IReadOnlyList<ExternalMangaVolumeDto>? volumeDetailsFromSource,
        CancellationToken ct)
    {
        if (volumeDetailsFromSource is { Count: > 0 })
        {
            return false;
        }

        if (providerResolver.Resolve("manga", MangaDexMetadataProvider.Source.Id) is not MangaDexMetadataProvider mangadex)
        {
            return false;
        }

        // The row's own title first, then the romanised one: MangaDex indexes romanised and English
        // names, so a title added from Shikimori only matches through its alt title.
        var details = await mangadex.GetVolumeDetailsByTitleAsync(
            [manga.Title, manga.RomajiTitle ?? string.Empty],
            ct);

        if (details.Count == 0)
        {
            return false;
        }

        var volumesBefore = manga.Volumes.Count;
        MediaMetadataApplier.ApplyRealVolumes(
            manga,
            details,
            volume => db.Entry(volume).State = EntityState.Added);

        return manga.Volumes.Count != volumesBefore;
    }
}