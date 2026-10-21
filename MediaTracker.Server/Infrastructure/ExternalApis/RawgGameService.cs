using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Extensions.Options;

namespace MediaTracker.Server.Infrastructure.ExternalApis;

public sealed record GameAchievementItem(string Name, string? Description, string? IconUrl);

public sealed record GameAchievementsResponse(
    int TotalCount,
    IReadOnlyList<GameAchievementItem> Achievements
);

public sealed record GameRelatedItem(
    string Id,
    string Title,
    string? CoverUrl,
    string? ReleaseDate,
    double? Score
);

/// <summary>
/// Talks to Steam and RAWG for the game-only panels (achievements, series, recommendations).
/// The endpoints stay thin and the "which RAWG id do we mean?" rule lives in one place.
/// </summary>
public sealed partial class RawgGameService(
    IHttpClientFactory httpClientFactory,
    IOptions<ExternalApiOptions> options,
    ILogger<RawgGameService> logger
)
{
    private const string SteamStoreUrl = "https://store.steampowered.com/api";
    private const string RawgApiUrl = "https://api.rawg.io/api";

    /// <summary>RAWG's largest accepted page size for this endpoint.</summary>
    private const int AchievementPageSize = 40;

    /// <summary>50 pages x 40 = 2000 achievements, above the largest known title (Payday, ~1300).</summary>
    private const int MaxAchievementPages = 50;

    /// <summary>
    /// Strict provider choice: a game is only ever asked of the source it was added with, so a Steam
    /// row can never carry RAWG's definitions and vice versa. Within Steam the community list comes
    /// first — it is the only public endpoint with every achievement (Payday 2: 1342, icons and
    /// descriptions included, no key) — while the store API's ~10 highlighted entries stay behind as
    /// a fallback.
    /// </summary>
    public async Task<GameAchievementsResponse> GetAchievementsAsync(
        string? steamAppId,
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        CancellationToken ct
    )
    {
        var sw = Stopwatch.StartNew();

        var fromSteam =
            string.Equals(externalSource, "steam", StringComparison.OrdinalIgnoreCase)
            || (!string.IsNullOrWhiteSpace(steamAppId)
                && !string.Equals(externalSource, "rawg", StringComparison.OrdinalIgnoreCase));

        if (fromSteam)
        {
            var appId = steamAppId ?? externalId;

            var community = await TryGetSteamCommunityAchievementsAsync(appId, ct);
            if (community is not null)
            {
                ExternalApiLog.Returned(logger, "Steam", community.Achievements.Count, sw.ElapsedMilliseconds);
                return community;
            }

            var store = await TryGetSteamStoreAchievementsAsync(appId, ct);
            if (store is not null)
            {
                ExternalApiLog.Returned(logger, "Steam", store.Achievements.Count, sw.ElapsedMilliseconds);
                return store;
            }

            logger.LogInformation(
                "[Storage] Steam answered no achievements for app '{AppId}' after {ElapsedMs}ms",
                appId,
                sw.ElapsedMilliseconds);
            return new GameAchievementsResponse(0, []);
        }

        var rawg = await TryGetRawgAchievementsAsync(rawgId, title, externalSource, externalId, ct);
        if (rawg is not null)
        {
            ExternalApiLog.Returned(logger, "RAWG", rawg.Achievements.Count, sw.ElapsedMilliseconds);
            return rawg;
        }

        logger.LogInformation(
            "[Storage] No achievement source answered for '{Title}' after {ElapsedMs}ms",
            title,
            sw.ElapsedMilliseconds);
        return new GameAchievementsResponse(0, []);
    }

    public async Task<IReadOnlyList<GameRelatedItem>> GetRelatedAsync(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(options.Value.RawgApiKey))
        {
            return [];
        }

        try
        {
            var rawgGameId = await ResolveRawgIdAsync(
                rawgId,
                title,
                externalSource,
                externalId,
                ct
            );
            if (rawgGameId is null)
            {
                return [];
            }

            var series = await GetAsync<RawgSeriesRoot>(
                $"{RawgApiUrl}/games/{rawgGameId}/game-series?page_size=20",
                ct
            );
            return series?.Results is { Count: > 0 } list
                ? Deduplicate(list, title, rawgGameId)
                : [];
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "RAWG series lookup failed for '{Title}'", title);
            return [];
        }
    }

    public async Task<IReadOnlyList<GameRelatedItem>> GetRecommendationsAsync(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(options.Value.RawgApiKey))
        {
            return [];
        }

        try
        {
            var rawgGameId = await ResolveRawgIdAsync(
                rawgId,
                title,
                externalSource,
                externalId,
                ct
            );
            if (rawgGameId is null)
            {
                logger.LogWarning(
                    "RAWG recommendations: could not resolve a game id for '{Title}'",
                    title
                );
                return [];
            }

            // ponytail: genre-based similarity, not real ML recommendations.
            // Ceiling: same-genre, popularity-ordered.
            // Note: RAWG /games/{id}/suggested (their CV-based "similar games") answers 401 on the
            // free plan — it is a paid Business feature. Revisit if the account is upgraded.
            var detail = await GetAsync<RawgDetailRoot>($"{RawgApiUrl}/games/{rawgGameId}", ct);
            var genreIds = detail?.Genres?.Select(g => g.Id).Where(id => id > 0).ToList() ?? [];
            if (genreIds.Count == 0)
            {
                logger.LogWarning("RAWG recommendations: game {Id} has no genres", rawgGameId);
                return [];
            }

            var genresParam = Uri.EscapeDataString(string.Join(',', genreIds));
            var url =
                $"{RawgApiUrl}/games?genres={genresParam}&exclude={Uri.EscapeDataString(rawgGameId)}&ordering=-rating&page_size=12";
            var similar = await GetAsync<RawgSearchRoot>(url, ct);

            return similar?.Results is { Count: > 0 } matches
                ? [.. matches.Where(g => !string.IsNullOrWhiteSpace(g.Name)).Select(ToRelatedItem)]
                : [];
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "RAWG recommendations failed for '{Title}'", title);
            return [];
        }
    }

    /// <summary>
    /// The caller may hold a RAWG id, an id from another provider, or nothing but a title. Resolve
    /// all three cases: an id from a different source means nothing to the RAWG API.
    /// </summary>
    private async Task<string?> ResolveRawgIdAsync(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        CancellationToken ct
    )
    {
        if (!string.IsNullOrWhiteSpace(rawgId))
        {
            return rawgId.Trim();
        }

        if (
            string.Equals(externalSource, "rawg", StringComparison.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(externalId)
        )
        {
            return externalId.Trim();
        }

        if (string.IsNullOrWhiteSpace(title))
        {
            return null;
        }

        var search = await GetAsync<RawgSearchRoot>(
            $"{RawgApiUrl}/games?search={Uri.EscapeDataString(title)}&page_size=1",
            ct
        );
        return search?.Results is { Count: > 0 } ? search.Results[0].Id.ToString() : null;
    }

    /// <summary>Store API: only the ~10 highlighted achievements, kept as a backup for when the
    /// community list cannot be reached.</summary>
    private async Task<GameAchievementsResponse?> TryGetSteamStoreAchievementsAsync(
        string? steamAppId,
        CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(steamAppId))
        {
            return null;
        }

        try
        {
            var url =
                $"{SteamStoreUrl}/appdetails?appids={Uri.EscapeDataString(steamAppId)}&l=english";
            var details = await GetAsync<Dictionary<string, SteamAppDetailsRoot>>(url, ct);

            if (
                details is not null
                && details.TryGetValue(steamAppId, out var wrapper)
                && wrapper.Data?.Achievements is { Total: > 0 } achievements
            )
            {
                var items = (achievements.Highlighted ?? [])
                    .Select(h => new GameAchievementItem(
                        h.LocalizedName ?? h.Name ?? "Achievement",
                        null,
                        h.Path
                    ))
                    .ToList();
                return new GameAchievementsResponse(achievements.Total, items);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(
                ex,
                "Steam store achievements lookup failed for '{SteamAppId}'",
                steamAppId
            );
        }

        return null;
    }

    /// <summary>
    /// The full community list from <c>steamcommunity.com/stats/{appId}/achievements/?xml=1</c>:
    /// completely open, no key, and it carries every achievement with icon and description even for
    /// 1000+ titles (Payday 2: 1342 rows) — which the store API's highlighted ten never could.
    /// Steam answers the ?xml=1 URL with HTML these days, so both payload shapes are parsed.
    /// </summary>
    private async Task<GameAchievementsResponse?> TryGetSteamCommunityAchievementsAsync(
        string? appId,
        CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(appId))
        {
            return null;
        }

        try
        {
            var url =
                $"https://steamcommunity.com/stats/{Uri.EscapeDataString(appId)}/achievements/?xml=1";
            var payload = await httpClientFactory.CreateClient().GetStringAsync(url, ct);
            var items = ParseSteamCommunityAchievements(payload);
            return items.Count > 0 ? new GameAchievementsResponse(items.Count, items) : null;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(
                ex,
                "Steam community achievements lookup failed for app '{AppId}'",
                appId
            );
            return null;
        }
    }

    private static List<GameAchievementItem> ParseSteamCommunityAchievements(string payload)
    {
        if (string.IsNullOrWhiteSpace(payload))
        {
            return [];
        }

        if (payload.Contains("achieveRow", StringComparison.OrdinalIgnoreCase))
        {
            var items = new List<GameAchievementItem>();
            foreach (Match row in AchieveRowRegex().Matches(payload))
            {
                var name = CleanAchievementText(row.Groups["name"].Value);
                if (name.Length == 0)
                {
                    continue;
                }

                var description = CleanAchievementText(row.Groups["desc"].Value);
                items.Add(new GameAchievementItem(
                    name,
                    description.Length > 0 ? description : null,
                    row.Groups["icon"].Value));
            }

            return items;
        }

        try
        {
            return ParseSteamCommunityXml(payload);
        }
        catch (System.Xml.XmlException)
        {
            return [];
        }
    }

    private static List<GameAchievementItem> ParseSteamCommunityXml(string payload)
    {
        static string? Field(XElement node, string name) =>
            node.Elements(name).FirstOrDefault()?.Value;

        var items = new List<GameAchievementItem>();
        foreach (var achievement in XDocument.Parse(payload).Descendants("achievement"))
        {
            var name = Field(achievement, "name");
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }

            items.Add(new GameAchievementItem(
                CleanAchievementText(name),
                CleanAchievementText(Field(achievement, "description") ?? string.Empty),
                Field(achievement, "iconOpen") ?? Field(achievement, "icon")));
        }

        return items;
    }

    private static string CleanAchievementText(string value) =>
        WebUtility.HtmlDecode(value ?? string.Empty).Trim();

    /// <summary>One <c>achieveRow</c> block: icon, heading and description of a single achievement.</summary>
    [GeneratedRegex(
        """<div class="achieveRow[^"]*">.*?<img src="(?<icon>[^"]+)".*?<h3>(?<name>.*?)</h3>(?:\s*<h5>(?<desc>.*?)</h5>)?""",
        RegexOptions.Singleline,
        10000)]
    private static partial Regex AchieveRowRegex();

    private async Task<GameAchievementsResponse?> TryGetRawgAchievementsAsync(
        string? rawgId,
        string? title,
        string? externalSource,
        string? externalId,
        CancellationToken ct
    )
    {
        if (string.IsNullOrWhiteSpace(options.Value.RawgApiKey))
        {
            return null;
        }

        try
        {
            var rawgGameId = await ResolveRawgIdAsync(
                rawgId,
                title,
                externalSource,
                externalId,
                ct
            );
            if (rawgGameId is null)
            {
                return null;
            }

            // The list is paginated: a single page_size=20 request truncated titles like Payday
            // (1000+ achievements) to a couple of dozen, so the pages are walked until the reported
            // total is covered. MaxAchievementPages caps a pathological game at a few hundred calls.
            var items = new List<GameAchievementItem>();
            var total = 0;

            for (var page = 1; page <= MaxAchievementPages; page++)
            {
                var achievements = await GetAsync<RawgAchievementsRoot>(
                    $"{RawgApiUrl}/games/{rawgGameId}/achievements?page_size={AchievementPageSize}&page={page}",
                    ct
                );

                if (achievements is null)
                {
                    break;
                }

                total = Math.Max(total, achievements.Count);

                var batch = achievements.Results ?? [];
                if (batch.Count == 0)
                {
                    break;
                }

                items.AddRange(
                    batch.Select(r => new GameAchievementItem(
                        r.Name ?? "Achievement",
                        r.Description,
                        r.Image
                    ))
                );

                if (items.Count >= total || batch.Count < AchievementPageSize)
                {
                    break;
                }
            }

            if (items.Count == 0)
            {
                return null;
            }

            return new GameAchievementsResponse(total, items);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "RAWG achievements lookup failed for '{Title}'", title);
            return null;
        }
    }

    private Task<T?> GetAsync<T>(string url, CancellationToken ct) =>
        httpClientFactory.CreateClient().GetFromJsonAsync<T>(WithApiKey(url), ct);

    private string WithApiKey(string url)
    {
        var key = Uri.EscapeDataString(options.Value.RawgApiKey);
        return url.Contains('?') ? $"{url}&key={key}" : $"{url}?key={key}";
    }

    private static IReadOnlyList<GameRelatedItem> Deduplicate(
        IReadOnlyList<RawgSeriesItem> list,
        string? title,
        string? rawgGameId
    )
    {
        var seenNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            title?.Trim() ?? string.Empty,
        };
        var seenIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            rawgGameId?.Trim() ?? string.Empty,
        };
        var results = new List<GameRelatedItem>();

        foreach (var game in list)
        {
            var id = game.Id.ToString();
            var name = (game.Name ?? string.Empty).Trim();
            if (string.IsNullOrWhiteSpace(name) || !seenIds.Add(id) || !seenNames.Add(name))
            {
                continue;
            }

            results.Add(
                new GameRelatedItem(
                    id,
                    name,
                    game.BackgroundImage,
                    game.Released,
                    ToScore(game.Rating)
                )
            );
        }

        return results;
    }

    private static GameRelatedItem ToRelatedItem(RawgSearchResultItem game) =>
        new(
            game.Id.ToString(),
            game.Name!,
            game.BackgroundImage,
            game.Released,
            ToScore(game.Rating)
        );

    /// <summary>RAWG scores are 0-10, the UI shows 0-20.</summary>
    private static double? ToScore(double? rating) =>
        rating is > 0 ? Math.Round(rating.Value * 2.0, 1) : null;

    private sealed class SteamAppDetailsRoot
    {
        [JsonPropertyName("data")]
        public SteamAppDetailsData? Data { get; set; }
    }

    private sealed class SteamAppDetailsData
    {
        [JsonPropertyName("achievements")]
        public SteamAchievementsBlock? Achievements { get; set; }
    }

    private sealed class SteamAchievementsBlock
    {
        [JsonPropertyName("total")]
        public int Total { get; set; }

        [JsonPropertyName("highlighted")]
        public List<SteamAchievementItem>? Highlighted { get; set; }
    }

    private sealed class SteamAchievementItem
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("path")]
        public string? Path { get; set; }

        [JsonPropertyName("localized_name")]
        public string? LocalizedName { get; set; }
    }

    private sealed class RawgSearchRoot
    {
        [JsonPropertyName("results")]
        public List<RawgSearchResultItem>? Results { get; set; }
    }

    private sealed class RawgSeriesRoot
    {
        [JsonPropertyName("results")]
        public List<RawgSeriesItem>? Results { get; set; }
    }

    private sealed class RawgDetailRoot
    {
        [JsonPropertyName("genres")]
        public List<RawgDetailGenre>? Genres { get; set; }
    }

    private sealed class RawgDetailGenre
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }
    }

    private sealed class RawgAchievementsRoot
    {
        [JsonPropertyName("count")]
        public int Count { get; set; }

        [JsonPropertyName("results")]
        public List<RawgAchievementResultItem>? Results { get; set; }
    }

    private sealed class RawgAchievementResultItem
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("description")]
        public string? Description { get; set; }

        [JsonPropertyName("image")]
        public string? Image { get; set; }
    }

    private sealed class RawgSearchResultItem
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("background_image")]
        public string? BackgroundImage { get; set; }

        [JsonPropertyName("released")]
        public string? Released { get; set; }

        [JsonPropertyName("rating")]
        public double? Rating { get; set; }
    }

    private sealed class RawgSeriesItem
    {
        [JsonPropertyName("id")]
        public long Id { get; set; }

        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("background_image")]
        public string? BackgroundImage { get; set; }

        [JsonPropertyName("released")]
        public string? Released { get; set; }

        [JsonPropertyName("rating")]
        public double? Rating { get; set; }
    }
}
