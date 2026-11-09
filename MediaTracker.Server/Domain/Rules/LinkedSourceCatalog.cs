using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>One external source bound to a media item.</summary>
public sealed record LinkedSourceDto(
    string Source,
    string ExternalId,
    string? Url,
    bool IsPrimary,
    string? Title,
    List<string>? ProvidedFields);

/// <summary>Payload of POST /api/media/{id}/linked-sources.</summary>
public sealed record LinkSourceRequest(
    string Source,
    string ExternalId,
    string? Url,
    string? Title,
    List<string>? ProvidedFields,
    bool? IsPrimary);

/// <summary>
/// Parses, seeds and mutates the <c>LinkedSourcesJson</c> blob of a <see cref="MediaItem"/>.
/// The stored shape is a JSON array of <see cref="LinkedSourceDto"/>; an empty blob seeds itself
/// from the item's own ExternalSource/ExternalId so the panel is never blank for existing rows.
/// </summary>
public static class LinkedSourceCatalog
{
    private static string NormalizeKey(string source) => source.Trim().ToLowerInvariant();

    public static List<LinkedSourceDto> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            var parsed = JsonSerializer.Deserialize(json, AppJsonSerializerContext.Default.ListLinkedSourceDto);
            return parsed is null ? [] : [.. parsed];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    public static string Serialize(IReadOnlyList<LinkedSourceDto> sources) =>
        JsonSerializer.Serialize(new List<LinkedSourceDto>(sources), AppJsonSerializerContext.Default.ListLinkedSourceDto);

    /// <summary>
    /// The item's sources, seeded with its own primary source when the blob is empty. The stored
    /// <c>IsPrimary</c> flag is authoritative: the crown decides the left "Источник данных" field,
    /// so forcing it onto <c>ExternalSource</c> every read made a user-switched primary impossible.
    /// Legacy blobs with no flag fall back to the item's own source, then to the first row. The
    /// primary row's field list is recomputed from what the entity actually holds.
    /// </summary>
    public static List<LinkedSourceDto> GetFor(MediaItem item)
    {
        var list = Parse(item.LinkedSourcesJson);
        if (list.Count == 0 && !string.IsNullOrWhiteSpace(item.ExternalSource))
        {
            list.Add(new LinkedSourceDto(
                item.ExternalSource,
                item.ExternalId ?? string.Empty,
                BuildSourcePageUrl(item.ExternalSource, item.ExternalId, item),
                true,
                item.Title,
                null));
        }

        if (list.Count > 0)
        {
            var primaryIndex = list.FindIndex(source => source.IsPrimary);
            if (primaryIndex < 0)
            {
                var ownKey = NormalizeSourceKey(item.ExternalSource);
                primaryIndex = ownKey.Length > 0
                    ? list.FindIndex(source => NormalizeSourceKey(source.Source) == ownKey)
                    : -1;
                if (primaryIndex < 0)
                {
                    primaryIndex = 0;
                }
            }

            for (var i = 0; i < list.Count; i++)
            {
                var isPrimary = i == primaryIndex;
                list[i] = list[i] with
                {
                    IsPrimary = isPrimary,
                    // The Shikimori page link is rebuilt on every read: the site's domain moves, so a
                    // stored URL would rot with the mirror that was live when the row was written.
                    Url = BuildSourcePageUrl(list[i].Source, list[i].ExternalId, item) ?? list[i].Url,
                    ProvidedFields = isPrimary ? CollectItemFields(item) : list[i].ProvidedFields,
                };
            }
        }

        AddRatingOnlySources(item, list);
        return list;
    }

    /// <summary>
    /// A source that only contributed a score never reaches <see cref="AppendFromExternal"/> with an
    /// external id, so it used to vanish from the panel. Any stored rating whose source is missing
    /// (or is present without the tag) gets a "Рейтинг" row, keeping the provenance honest.
    /// </summary>
    private static void AddRatingOnlySources(MediaItem item, List<LinkedSourceDto> list)
    {
        foreach (var rating in MediaMetadataApplier.ReadStoredRatings(item.ExternalRatingsJson))
        {
            if (string.IsNullOrWhiteSpace(rating.Source))
            {
                continue;
            }

            var key = NormalizeSourceKey(rating.Source);
            var index = list.FindIndex(source => NormalizeSourceKey(source.Source) == key);
            if (index >= 0)
            {
                var row = list[index];
                if (row.ProvidedFields?.Contains("Рейтинг", StringComparer.OrdinalIgnoreCase) == true)
                {
                    continue;
                }

                list[index] = row with { ProvidedFields = MergeFields(row.ProvidedFields, ["Рейтинг"]) };
                continue;
            }

            list.Add(new LinkedSourceDto(rating.Source, string.Empty, null, false, null, ["Рейтинг"]));
        }

        if (item.ExternalRating is > 0 && !string.IsNullOrWhiteSpace(item.ExternalSource))
        {
            var key = NormalizeSourceKey(item.ExternalSource);
            var index = list.FindIndex(source => NormalizeSourceKey(source.Source) == key);
            if (index >= 0)
            {
                var row = list[index];
                if (row.ProvidedFields?.Contains("Рейтинг", StringComparer.OrdinalIgnoreCase) != true)
                {
                    list[index] = row with { ProvidedFields = MergeFields(row.ProvidedFields, ["Рейтинг"]) };
                }
            }
            else
            {
                list.Add(new LinkedSourceDto(item.ExternalSource, item.ExternalId ?? string.Empty, null, false, null, ["Рейтинг"]));
            }
        }
    }

    /// <summary>Alias-tolerant comparison: blobs store display names ("MangaLib"), the row may carry the provider id.</summary>
    private static string NormalizeSourceKey(string? source) =>
        string.IsNullOrWhiteSpace(source) ? string.Empty : MediaMerger.NormalizeSourceKey(source);

    /// <summary>
    /// The web page of a bound Shikimori or AnimeLib record, rebuilt on every read: Shikimori's
    /// domain moves between mirrors, and AnimeLib's canonical shape is the versioned host with
    /// mandatory /ru/anime/ prefixes. Every other source's page link is built client-side, so null
    /// leaves the stored URL untouched.
    /// </summary>
    private static string? BuildSourcePageUrl(string? source, string? externalId, MediaItem item)
    {
        if (string.IsNullOrWhiteSpace(source) || string.IsNullOrWhiteSpace(externalId))
        {
            return null;
        }

        var key = MediaMerger.NormalizeSourceKey(source);
        if (key.Contains("shikimori", StringComparison.OrdinalIgnoreCase))
        {
            var section = item is TvShow { IsAnime: true } or Movie { IsAnime: true } ? "animes" : "mangas";
            return $"https://{ShikimoriMirrors.ActiveDomain}/{section}/{Uri.EscapeDataString(externalId.Trim())}";
        }

        if (key.Contains("animelib", StringComparison.OrdinalIgnoreCase))
        {
            var slug = externalId.Trim();
            // A slug may arrive with the site's own prefixes already on ("ru/anime/8231--x");
            // both are stripped so the canonical shape is never doubled.
            foreach (var prefix in (string[])["ru/", "anime/"])
            {
                if (slug.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    slug = slug[prefix.Length..];
                }
            }

            return $"https://v5.animelib.org/ru/anime/{Uri.EscapeDataString(slug)}";
        }

        return null;
    }

    /// <summary>Writes the list back; a single primary source is enforced when any is flagged.</summary>
    public static void SaveFor(MediaItem item, IReadOnlyList<LinkedSourceDto> sources)
    {
        var primaryCount = sources.Count(s => s.IsPrimary);
        if (primaryCount > 1)
        {
            var primarySeen = false;
            sources =
            [
                .. sources.Select(s =>
                {
                    if (!s.IsPrimary || primarySeen) return s with { IsPrimary = false };
                    primarySeen = true;
                    return s;
                }),
            ];
        }

        item.LinkedSourcesJson = sources.Count > 0 ? Serialize(sources) : null;

        // The left "Источник данных" field follows the crown: the base record is whichever source
        // the user marked primary, so refresh and the aggregator query it by its own id next time.
        var primary = sources.FirstOrDefault(source => source.IsPrimary);
        if (primary is not null && !string.IsNullOrWhiteSpace(primary.Source))
        {
            item.ExternalSource = primary.Source;
            if (!string.IsNullOrWhiteSpace(primary.ExternalId))
            {
                item.ExternalId = primary.ExternalId;
            }
        }

        item.MarkUpdated();
    }

    /// <summary>
    /// Registers a source answered by an enrichment/import: appends when the source is not bound
    /// yet, refreshes the external id of an existing binding, never steals the primary flag. The
    /// contributed field list grows by union, so a second enrichment that adds a trailer on top of
    /// the genres a source already supplied keeps both entries.
    /// </summary>
    public static void AppendFromExternal(
        MediaItem item,
        string? source,
        string? externalId,
        string? title,
        List<string>? providedFields = null)
    {
        if (string.IsNullOrWhiteSpace(source)
            || source.Equals("offline", StringComparison.OrdinalIgnoreCase)
            || source.StartsWith("offline", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var hasFields = providedFields is { Count: > 0 };
        // A rating-only contribution has no external id: it is still a real source, and dropping it
        // was why AniList/AnimeLib disappeared from the panel after a score-only enrichment.
        if (string.IsNullOrWhiteSpace(externalId) && !hasFields)
        {
            return;
        }

        var normalizedId = externalId?.Trim() ?? string.Empty;
        var list = Parse(item.LinkedSourcesJson);
        var existing = list.FirstOrDefault(s => NormalizeKey(s.Source) == NormalizeKey(source));
        if (existing is not null)
        {
            var mergedFields = MergeFields(existing.ProvidedFields, providedFields);
            // A provider that answers without an id must not erase the id already bound.
            var nextId = string.IsNullOrWhiteSpace(normalizedId) ? existing.ExternalId : normalizedId;
            if (existing.ExternalId == nextId
                && (mergedFields ?? []).SequenceEqual(existing.ProvidedFields ?? [], StringComparer.Ordinal))
            {
                return;
            }

            var updated = existing with
            {
                ExternalId = nextId,
                Title = string.IsNullOrWhiteSpace(existing.Title) ? title : existing.Title,
                ProvidedFields = mergedFields,
            };
            list[list.IndexOf(existing)] = updated;
        }
        else
        {
            list.Add(new LinkedSourceDto(source, normalizedId, null, false, title, providedFields));
        }

        item.LinkedSourcesJson = Serialize(list);
    }

    private static List<string>? MergeFields(List<string>? current, List<string>? incoming)
    {
        if (incoming is not { Count: > 0 }) return current;
        if (current is not { Count: > 0 }) return incoming;

        var merged = new List<string>(current);
        foreach (var field in incoming)
        {
            if (!merged.Contains(field, StringComparer.OrdinalIgnoreCase))
            {
                merged.Add(field);
            }
        }

        return merged;
    }

    /// <summary>
    /// What the item actually holds, as the provenance of the source that supplied the base record:
    /// every entry below is backed by a present value on the row, never by a static assumption. The
    /// labels follow the media type's vocabulary — voice cast for anime, actors for films, characters
    /// and authors/artists for manga and books.
    /// </summary>
    private static List<string> CollectItemFields(MediaItem item)
    {
        var fields = new List<string>();

        if (!string.IsNullOrWhiteSpace(item.Title)) fields.Add("Название");
        if (!string.IsNullOrWhiteSpace(item.ReleaseStatus)) fields.Add("Статус");
        if (item.AltTitles is not null) fields.Add("Альт. названия");

        switch (item)
        {
            case TvShow show when show.Seasons.Count > 0:
                fields.Add("Серии");
                break;
            case Manga manga:
                if (manga.TotalChapters is > 0) fields.Add("Главы");
                if (manga.TotalVolumes is > 0) fields.Add("Тома");
                break;
            case Book book:
                if (book.TotalChapters is > 0) fields.Add("Главы");
                if (book.TotalPages > 0) fields.Add("Страницы");
                break;
        }

        if (item.ReleaseDate is not null || item.EndDate is not null || item.ReleaseYear is not null)
        {
            fields.Add("Даты выхода");
        }

        if (item.CoverUrl is not null || item.CoversJson is not null) fields.Add("Постер");

        var isAnime = item is TvShow { IsAnime: true } or Movie { IsAnime: true };
        var isPrint = item is Manga or Book;
        if (item.CastJson is not null)
        {
            fields.Add(isAnime ? "Сэйю (каст)" : isPrint ? "Персонажи" : "Актёры");
        }

        if (item.StaffJson is not null)
        {
            fields.Add(isPrint ? "Авторы/Художники" : "Съёмочная группа");
        }

        switch (item)
        {
            case Movie movie:
                if (movie.DurationMinutes > 0) fields.Add("Хронометраж");
                if (!string.IsNullOrWhiteSpace(movie.Studio)) fields.Add("Студия");
                if (!string.IsNullOrWhiteSpace(movie.Director)) fields.Add("Режиссёр");
                break;
            case TvShow tv when !string.IsNullOrWhiteSpace(tv.Studio):
                if (tv.EpisodeDurationMinutes is > 0) fields.Add("Хронометраж");
                fields.Add("Студия");
                break;
            case Manga manga when !string.IsNullOrWhiteSpace(manga.Author):
                fields.Add("Автор");
                break;
            case Book book when !string.IsNullOrWhiteSpace(book.Author):
                fields.Add("Автор");
                break;
            case VideoGame game:
                if (!string.IsNullOrWhiteSpace(game.Studio)) fields.Add("Студия");
                if (!string.IsNullOrWhiteSpace(game.Platform)) fields.Add("Платформа");
                break;
        }

        if (!string.IsNullOrWhiteSpace(item.Genres)) fields.Add("Жанры");
        if (!string.IsNullOrWhiteSpace(item.TrailerVideoId)) fields.Add("Трейлер");
        if (item.ExternalRating is > 0 || item.ExternalRatingsJson is not null) fields.Add("Рейтинг");
        if (!string.IsNullOrWhiteSpace(item.Description)) fields.Add("Синопсис");

        return fields;
    }
}
