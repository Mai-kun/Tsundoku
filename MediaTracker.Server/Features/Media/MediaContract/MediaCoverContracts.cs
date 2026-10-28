using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Rules;

namespace MediaTracker.Server.Features.Media.MediaContract;

/// <summary>
/// One saved cover variant of a title. <see cref="ThumbUrl"/> is what the grid renders and what the
/// active row's <c>CoverUrl</c> points at; <see cref="OriginalUrl"/> is the same folder's full-size
/// rendition, so the detail page rewrites the filename instead of re-downloading.
/// </summary>
public sealed record MediaCoverItemDto(string Id, string ThumbUrl, string OriginalUrl, string? Source, DateTime AddedAt);

/// <summary>Body of POST /api/media/{id}/covers when the cover is added by URL.</summary>
public sealed record AddCoverRequest(string Url, string? Source = null, bool SetAsActive = false);

/// <summary>
/// Reads and writes the <c>CoversJson</c> gallery column. Lives next to
/// <see cref="MediaJsonCache"/> because a cover added by one slice must survive whatever writes the
/// row next, and the stored shape is exactly the serialised DTO list.
/// </summary>
public static class MediaCoverCollection
{
    /// <summary>Stable identifier for the pre-gallery cover that still lives in the "cover" folder.</summary>
    public const string LegacyCoverId = "legacy-cover";

    public static List<MediaCoverItemDto> Parse(string? coversJson) =>
        [.. MediaJsonCache.Deserialize<MediaCoverItemDto>(coversJson)];

    public static string? Serialize(IReadOnlyList<MediaCoverItemDto> covers) =>
        covers.Count == 0
            ? null
            : JsonSerializer.Serialize(covers, AppJsonSerializerContext.Default.IReadOnlyListMediaCoverItemDto);

    /// <summary>
    /// A title that got its cover before the gallery existed has the files on disk but an empty
    /// <c>CoversJson</c>. Registers that legacy cover as the first gallery entry so switching to a
    /// newer variant (or deleting it) cannot orphan the only poster the row has.
    /// </summary>
    public static List<MediaCoverItemDto> EnsureLegacyCoverRegistered(MediaItem item)
    {
        var covers = Parse(item.CoversJson);

        if (covers.Count > 0 || item.CoverUrl is not { } coverUrl || MediaMetadataApplier.IsExternalUrl(coverUrl))
        {
            return covers;
        }

        // Only the current per-title layout has a sibling original.webp; anything else (an external
        // URL kept after a failed download, or a pre-gallery /covers/{id}.webp row) has no pair.
        var thumb = coverUrl.Split('?')[0];
        if (!thumb.StartsWith($"/media-assets/{item.Id}/cover/", StringComparison.Ordinal)
            || !thumb.EndsWith("thumb.webp", StringComparison.Ordinal))
        {
            return covers;
        }

        covers.Insert(0, new MediaCoverItemDto(
            LegacyCoverId,
            thumb,
            thumb.Replace("thumb.webp", "original.webp", StringComparison.Ordinal),
            null,
            item.UpdatedAt));

        item.CoversJson = Serialize(covers);
        return covers;
    }
}
