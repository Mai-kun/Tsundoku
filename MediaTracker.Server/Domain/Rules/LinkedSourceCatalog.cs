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
        JsonSerializer.Serialize(sources, AppJsonSerializerContext.Default.ListLinkedSourceDto);

    /// <summary>
    /// The item's sources, seeded with its own primary source when the blob is empty. The row that
    /// matches the item's own <c>ExternalSource</c> — the source the title was added from — is
    /// ALWAYS the primary one: the flag is re-imposed on every read, so a stale blob (a legacy row
    /// that lost the flag, or an old switch that only flipped flags) can never leave the panel
    /// without the crown on the true base record. That row's field list is likewise recomputed from
    /// what the entity actually holds.
    /// </summary>
    public static List<LinkedSourceDto> GetFor(MediaItem item)
    {
        var list = Parse(item.LinkedSourcesJson);
        if (list.Count == 0 && !string.IsNullOrWhiteSpace(item.ExternalSource))
        {
            list.Add(new LinkedSourceDto(
                item.ExternalSource,
                item.ExternalId ?? string.Empty,
                null,
                true,
                item.Title,
                null));
        }

        var ownKey = NormalizeSourceKey(item.ExternalSource);
        var ownRowFound = false;
        var anyPrimaryLeft = false;
        for (var i = 0; i < list.Count; i++)
        {
            var isOwn = ownKey.Length > 0 && NormalizeSourceKey(list[i].Source) == ownKey;
            ownRowFound |= isOwn;
            var isPrimary = ownKey.Length > 0 ? isOwn : list[i].IsPrimary;
            anyPrimaryLeft |= isPrimary;
            list[i] = list[i] with
            {
                IsPrimary = isPrimary,
                ProvidedFields = isOwn || isPrimary ? CollectItemFields(item) : list[i].ProvidedFields,
            };
        }

        // An item whose own source vanished from the blob (legacy row, manual edit) still shows a
        // crowned record: the first entry represents the base record until the blob is repaired.
        if (!anyPrimaryLeft && list.Count > 0)
        {
            list[0] = list[0] with { IsPrimary = true, ProvidedFields = CollectItemFields(item) };
        }

        return list;
    }

    /// <summary>Alias-tolerant comparison: blobs store display names ("MangaLib"), the row may carry the provider id.</summary>
    private static string NormalizeSourceKey(string? source) =>
        string.IsNullOrWhiteSpace(source) ? string.Empty : MediaMerger.NormalizeSourceKey(source);

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
            || string.IsNullOrWhiteSpace(externalId)
            || source.Equals("offline", StringComparison.OrdinalIgnoreCase)
            || source.StartsWith("offline", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var list = Parse(item.LinkedSourcesJson);
        var existing = list.FirstOrDefault(s => NormalizeKey(s.Source) == NormalizeKey(source));
        if (existing is not null)
        {
            var mergedFields = MergeFields(existing.ProvidedFields, providedFields);
            if (existing.ExternalId == externalId
                && (mergedFields ?? []).SequenceEqual(existing.ProvidedFields ?? [], StringComparer.Ordinal))
            {
                return;
            }

            var updated = existing with
            {
                ExternalId = externalId,
                Title = string.IsNullOrWhiteSpace(existing.Title) ? title : existing.Title,
                ProvidedFields = mergedFields,
            };
            list[list.IndexOf(existing)] = updated;
        }
        else
        {
            list.Add(new LinkedSourceDto(source, externalId, null, false, title, providedFields));
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
