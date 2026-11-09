using System.Globalization;
using System.Net;
using System.Net.Sockets;
using MediaTracker.Server.Common.Json;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.Media.Import;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using Microsoft.Extensions.Logging;

namespace MediaTracker.Server.Infrastructure.ExternalApis.Providers.Shikimori;

public sealed class ShikimoriMetadataProvider(
    IHttpClientFactory httpClientFactory,
    [ServiceKey] string? serviceKey = null,
    ILogger<ShikimoriMetadataProvider>? logger = null) : MetadataProviderBase(Source)
{
    public static MetadataSourceDescriptor Source { get; } = new(
        Id: "shikimori",
        Name: "Shikimori",
        Description: "Anime & manga metadata and community ratings provider",
        MediaTypes: ["anime", "manga", "book"],
        BaseAddress: "https://shikimori.io/api/",
        Priority: 2,
        UserAgent: "MediaTracker/1.0 (Tsundoku)");

    private readonly string _mediaType =
        serviceKey?.Contains("book", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.Contains("novel", StringComparison.OrdinalIgnoreCase) is true ||
        serviceKey?.Contains("ranobe", StringComparison.OrdinalIgnoreCase) is true
            ? "book"
            : (serviceKey?.Contains("manga", StringComparison.OrdinalIgnoreCase) is true ? "manga" : "anime");

    /// <summary>Answers that mean the MIRROR is broken, not the record: walk to the next one.</summary>
    private static readonly HttpStatusCode[] MirrorDownStatuses =
    [
        HttpStatusCode.NotFound,
        HttpStatusCode.BadGateway,
        HttpStatusCode.ServiceUnavailable,
        (HttpStatusCode)521, // Cloudflare "web server is down" — the classic dead-mirror answer.
    ];

    public override async Task<IReadOnlyList<ExternalMediaDto>> SearchAsync(string query, CancellationToken ct)
    {
        var cleaned = MediaTitleHelper.StripGarbageSuffixes(query);
        var effectiveQuery = !string.IsNullOrWhiteSpace(cleaned) ? cleaned : query;
        // Books go through the dedicated /api/ranobe endpoint rather than mangas with a kind filter:
        // kind=light_novel hides web novels and book editions that ranobe serves without one.
        var endpoint = _mediaType switch
        {
            "book" => $"ranobe?search={Uri.EscapeDataString(effectiveQuery)}&limit=10",
            "manga" => $"mangas?search={Uri.EscapeDataString(effectiveQuery)}&limit=10",
            _ => $"animes?search={Uri.EscapeDataString(effectiveQuery)}&limit=10"
        };

        try
        {
            using var response = await SendWithFailoverAsync(domain => BuildGetRequest(domain, endpoint), ct);
            var items = await response.Content.ReadFromJsonAsync(
                AppJsonSerializerContext.Default.ListShikimoriItem, ct);
            if (items is null || items.Count == 0)
            {
                return [];
            }

            return items.ConvertAll(item => MapItem(item, _mediaType));
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    public override async Task<ExternalMediaDto?> GetDetailsAsync(string externalId, string title, CancellationToken ct)
    {
        var endpoint = _mediaType switch
        {
            "book" => $"ranobe/{externalId}",
            "manga" => $"mangas/{externalId}",
            _ => $"animes/{externalId}"
        };

        try
        {
            using var response = await SendWithFailoverAsync(domain => BuildGetRequest(domain, endpoint), ct);
            var item = await response.Content.ReadFromJsonAsync(
                AppJsonSerializerContext.Default.ShikimoriItem, ct);

            return item is null ? null : MapItem(item, _mediaType);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
    }

    /// <summary>
    /// Related titles from Shikimori's own <c>GET /api/{type}/{id}/related</c> — the same tree the
    /// site renders, served per bucket: <c>animes</c>, <c>mangas</c> or <c>ranobe</c>. Each row
    /// inlines the neighbour, so one request fills the whole tab; the Russian label
    /// (<c>relation_russian</c>) is deliberately not copied into the payload — <see cref="MapRelationType"/>
    /// emits the canonical key the Related tab already localises, which keeps every source answering
    /// in one vocabulary.
    ///
    /// Shikimori shares MyAnimeList's id space, so the id a row carries works here directly — no
    /// AniList detour, and no wrong-title matches from looking that id up elsewhere.
    /// </summary>
    public async Task<IReadOnlyList<ExternalRelationDto>> GetRelationsAsync(
        string? externalId,
        string? mediaType,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(externalId) || !long.TryParse(externalId, out _))
        {
            return [];
        }

        // The bucket the row was added from decides the tree; an unrecognised type falls back to
        // whatever this registered instance serves.
        var bucket = mediaType ?? _mediaType;
        var segment = bucket switch
        {
            "anime" => "animes",
            "manga" => "mangas",
            "book" => "ranobe",
            _ => _mediaType switch
            {
                "book" => "ranobe",
                "manga" => "mangas",
                _ => "animes",
            }
        };
        var endpoint = $"{segment}/{externalId}/related";

        try
        {
            using var response = await SendWithFailoverAsync(domain => BuildGetRequest(domain, endpoint), ct);
            var entries = await response.Content.ReadFromJsonAsync(
                AppJsonSerializerContext.Default.ListShikimoriRelatedEntry, ct);

            var relations = new List<ExternalRelationDto>();
            var seen = new HashSet<long>();
            foreach (var entry in entries ?? [])
            {
                var target = entry?.Target;
                if (target is null || !seen.Add(target.Id))
                {
                    continue;
                }

                // A novel answers in the manga slot of the payload; MapItem's kind logic puts it back
                // in the book bucket where it belongs.
                var targetType = entry!.Anime is not null ? "anime" : "manga";
                relations.Add(new ExternalRelationDto(
                    MapRelationType(entry.Relation),
                    MapItem(target, targetType)));
            }

            return relations;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // An unreadable mirror answer is a missing panel, not an error the tab should show.
            return [];
        }
    }

    /// <summary>
    /// Shikimori's relation vocabulary → the canonical keys the Related tab groups on. The API
    /// spells the kinds in prose ("Side Story", "Alternative Version"), so the match runs on a
    /// space→underscore casefold. "source" is the title the anime was adapted from, so it lands on
    /// ADAPTATION; a recap ("summary") has no bucket of its own and reports as OTHER instead of
    /// being dropped.
    /// </summary>
    public static string MapRelationType(string? relation) =>
        (relation ?? string.Empty).Trim().ToLowerInvariant().Replace(' ', '_') switch
        {
            "sequel" => "SEQUEL",
            "prequel" => "PREQUEL",
            "adaptation" or "source" => "ADAPTATION",
            "spin_off" => "SPIN_OFF",
            "side_story" => "SIDE_STORY",
            "alternative" or "alternative_version" => "ALTERNATIVE",
            "character" => "CHARACTER",
            _ => "OTHER",
        };

    /// <summary>
    /// Absolute URL against the given mirror: the named client's BaseAddress is informational once
    /// the failover owns which domain actually answers.
    /// </summary>
    private static HttpRequestMessage BuildGetRequest(string domain, string endpoint) =>
        new(HttpMethod.Get, $"https://{domain}/api/{endpoint}");

    /// <summary>
    /// Mirror failover around every Shikimori call. The active domain answers first; a network
    /// exception (timeout, connection refused/reset) or a mirror-down status (404/502/503/521)
    /// walks the remaining mirrors — the first one whose answer succeeds is promoted to active and
    /// serves the request that triggered the walk. The named client carries a 4 s timeout, so a
    /// dead mirror costs seconds, not minutes.
    /// </summary>
    private async Task<HttpResponseMessage> SendWithFailoverAsync(
        Func<string, HttpRequestMessage> requestFactory,
        CancellationToken ct)
    {
        Exception? failure = null;
        var active = ShikimoriMirrors.ActiveDomain;

        try
        {
            var response = await TryMirrorAsync(active, requestFactory, ct).ConfigureAwait(false);
            if (!IsMirrorDown(response.StatusCode))
            {
                return response;
            }

            response.Dispose();
            failure = new HttpRequestException(
                $"Shikimori mirror '{active}' answered {(int)response.StatusCode}.");
        }
        catch (Exception ex) when (IsTransientNetworkError(ex, ct))
        {
            failure = ex;
        }

        foreach (var mirror in ShikimoriMirrors.Mirrors)
        {
            if (string.Equals(mirror, active, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            try
            {
                var response = await TryMirrorAsync(mirror, requestFactory, ct).ConfigureAwait(false);
                if (IsMirrorDown(response.StatusCode))
                {
                    response.Dispose();
                    continue;
                }

                ShikimoriMirrors.SetActive(mirror);
                logger?.LogWarning("[Shikimori] Active mirror changed to {Domain}", ShikimoriMirrors.ActiveDomain);
                return response;
            }
            catch (Exception ex) when (IsTransientNetworkError(ex, ct))
            {
                // Mirror unreachable too: the walk continues.
            }
        }

        throw failure ?? new HttpRequestException("All Shikimori mirrors failed.");
    }

    private async Task<HttpResponseMessage> TryMirrorAsync(
        string domain,
        Func<string, HttpRequestMessage> requestFactory,
        CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(Id);
        return await client
            .SendAsync(requestFactory(domain), HttpCompletionOption.ResponseHeadersRead, ct)
            .ConfigureAwait(false);
    }

    private static bool IsMirrorDown(HttpStatusCode statusCode) =>
        MirrorDownStatuses.Contains(statusCode);

    /// <summary>Network-level trouble only; a caller cancellation is never a mirror's fault.</summary>
    private static bool IsTransientNetworkError(Exception ex, CancellationToken ct) =>
        ex is HttpRequestException or SocketException
        || (ex is OperationCanceledException or TaskCanceledException) && !ct.IsCancellationRequested;

    private static ExternalMediaDto MapItem(ShikimoriItem item, string type)
    {
        var cover = item.Image?.Original ?? item.Image?.Preview;
        if (!string.IsNullOrWhiteSpace(cover) && cover.StartsWith('/'))
        {
            // Relative image paths ride the LIVE mirror, not a baked-in domain: a cover link must
            // survive the next domain move the same way the API calls do.
            cover = $"https://{ShikimoriMirrors.ActiveDomain}{cover}";
        }

        double? score = null;
        if (!string.IsNullOrWhiteSpace(item.Score) && double.TryParse(item.Score, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedScore) && parsedScore > 0)
        {
            score = parsedScore;
        }

        var ratings = new List<ExternalRatingDto>();
        if (score.HasValue)
        {
            ratings.Add(new ExternalRatingDto
            {
                Source = "Shikimori",
                Rating = Math.Round(score.Value, 1),
                Votes = null
            });
        }

        int? releaseYear = null;
        if (!string.IsNullOrWhiteSpace(item.AiredOn) && DateTime.TryParse(item.AiredOn, out var airedDate))
        {
            releaseYear = airedDate.Year;
        }

        var author = item.Authors?.FirstOrDefault(a => !string.IsNullOrWhiteSpace(a.Russian) || !string.IsNullOrWhiteSpace(a.Name));
        var authorName = author is not null ? (!string.IsNullOrWhiteSpace(author.Russian) ? author.Russian : author.Name) : null;
        var isNovel = type == "book" || string.Equals(item.Kind, "light_novel", StringComparison.OrdinalIgnoreCase) || string.Equals(item.Kind, "novel", StringComparison.OrdinalIgnoreCase);

        var resolvedType = (type == "book" || isNovel) ? "book" : (type == "anime" ? "anime" : "manga");
        var mangaFormat = resolvedType switch
        {
            "book" => "light_novel",
            "manga" => "manga",
            _ => null
        };

        return new ExternalMediaDto
        {
            ExternalId = item.Id.ToString(CultureInfo.InvariantCulture),
            ExternalSource = "Shikimori",
            Title = !string.IsNullOrWhiteSpace(item.Russian) ? item.Russian : item.Name,
            OriginalTitle = item.Japanese?.FirstOrDefault(j => !string.IsNullOrWhiteSpace(j)) ?? item.Name,
            RomajiTitle = item.Name,
            CoverUrl = cover,
            Description = item.Description,
            Author = authorName,
            ReleaseYear = releaseYear,
            ReleaseDate = item.AiredOn,
            EndDate = item.ReleasedOn,
            // Shikimori answers "released"/"ongoing"/"anons" — folded into the canonical
            // vocabulary here so stored rows never carry a provider-specific spelling again.
            ReleaseStatus = ReleaseStatusRules.NormalizeStatus(item.Status),
            Type = resolvedType,
            MangaFormat = mangaFormat,
            TotalCount = resolvedType == "anime" ? item.Episodes : (item.Chapters is > 0 ? item.Chapters : item.Volumes),
            Chapters = item.Chapters,
            Volumes = item.Volumes,
            Rating = score,
            Ratings = ratings,
            Synonyms = item.Synonyms is { Count: > 0 } syns ? [.. syns.Where(s => !string.IsNullOrWhiteSpace(s))] : null,
            Genres = item.Genres is { Count: > 0 }
                ? item.Genres
                    .Select(g => !string.IsNullOrWhiteSpace(g.Russian) ? g.Russian : g.Name)
                    .Where(g => !string.IsNullOrWhiteSpace(g))
                    .Select(g => g!)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList()
                : null
        };
    }
}
