using System.Text.Json;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Domain.Rules;

/// <summary>One external source bound to a media item.</summary>
public sealed record LinkedSourceDto(
    string Source,
    string ExternalId,
    string? Url,
    bool IsPrimary,
    string? Title,
    string? Details);

/// <summary>Payload of POST /api/media/{id}/linked-sources.</summary>
public sealed record LinkSourceRequest(
    string Source,
    string ExternalId,
    string? Url,
    string? Title,
    string? Details,
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

    /// <summary>The item's sources, seeded with its own primary source when the blob is empty.</summary>
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

        return list;
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
        item.MarkUpdated();
    }

    /// <summary>
    /// Registers a source answered by an enrichment/import: appends when the source is not bound
    /// yet, refreshes the external id of an existing binding, never steals the primary flag.
    /// </summary>
    public static void AppendFromExternal(MediaItem item, string? source, string? externalId, string? title)
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
            if (existing.ExternalId == externalId) return;
            var updated = existing with
            {
                ExternalId = externalId,
                Title = string.IsNullOrWhiteSpace(existing.Title) ? title : existing.Title,
            };
            list[list.IndexOf(existing)] = updated;
        }
        else
        {
            list.Add(new LinkedSourceDto(source, externalId, null, false, title, null));
        }

        item.LinkedSourcesJson = Serialize(list);
    }
}
