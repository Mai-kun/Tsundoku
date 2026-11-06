using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.ExternalApis.Abstractions;
using MediaTracker.Server.Infrastructure.ExternalApis.Common;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;

namespace MediaTracker.Server.Features.Media.Calendar;

public sealed record CalendarScheduleDto(
    DateOnly From,
    DateOnly To,
    IReadOnlyList<CalendarDayDto> Days);

public sealed record CalendarDayDto(
    DateOnly Date,
    IReadOnlyList<CalendarItemDto> Items);

/// <summary>One calendar page entry: a scheduled auto-check, a dated episode or a planned release.</summary>
public sealed record CalendarItemDto(
    Guid MediaId,
    string Title,
    string Type,
    string? CoverUrl,
    int? CurrentProgress,
    int? TotalCount,
    /// <summary>"auto_refresh" (scheduled background check), "air_date" (a dated episode) or "release" (a planned title's release date).</summary>
    string Kind,
    string? Details,
    int? EpisodeNumber,
    int? SeasonNumber,
    bool IsAnime = false);

/// <summary>
/// One deadline the user can still make if they catch up: an airing episode they are behind on, or
/// a franchise sequel whose previous part is not finished yet.
/// </summary>
public sealed record BacklogDeadlineDto(
    Guid MediaId,
    string Title,
    string Type,
    string? CoverUrl,
    /// <summary>"air_date" (behind on an ongoing) or "release" (a sequel with an unfinished previous part).</summary>
    string Kind,
    DateOnly DeadlineDate,
    int DaysLeft,
    int? EpisodeNumber,
    int? SeasonNumber,
    /// <summary>Episodes/chapters left to catch up before the premiere; null for franchise sequels.</summary>
    int? BehindCount,
    /// <summary>The previous franchise part to finish first; null for ongoing catch-ups.</summary>
    string? BlockerTitle,
    int? BlockerProgress,
    int? BlockerTotalCount);

/// <summary>
/// The collection-side shape of a calendar event: everything both the JSON schedule, the .ics feed
/// and the backlog widget need, including franchise coordinates for sequel detection.
/// </summary>
internal sealed record CalendarEventRow(
    DateOnly Date,
    Guid MediaId,
    string Title,
    string Type,
    string? CoverUrl,
    int? CurrentProgress,
    int? TotalCount,
    string Kind,
    string? Details,
    int? EpisodeNumber,
    int? SeasonNumber,
    bool IsAnime,
    Guid? FranchiseId = null,
    int? FranchiseOrder = null)
{
    public CalendarItemDto ToItemDto() => new(
        MediaId, Title, Type, CoverUrl, CurrentProgress, TotalCount,
        Kind, Details, EpisodeNumber, SeasonNumber, IsAnime);
}

public static class CalendarEndpoints
{
    public static IEndpointRouteBuilder MapCalendarEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/media");

        // The calendar needs a breached range to mean something sane; silently swapping the ends
        // would render a month the caller did not ask for.
        group.MapGet("/calendar", async (
                AppDbContext db,
                [FromQuery] DateOnly? from,
                [FromQuery] DateOnly? to,
                CancellationToken ct) =>
            {
                var today = DateOnly.FromDateTime(DateTime.UtcNow);
                var monthStart = new DateOnly(today.Year, today.Month, 1);
                var rangeStart = from ?? monthStart;
                var rangeEnd = to ?? monthStart.AddMonths(1).AddDays(-1).AddDays(7);

                if (rangeStart > rangeEnd)
                {
                    return Results.BadRequest(new
                    {
                        problem = "Диапазон дат некорректен: 'from' должна быть не позже 'to'.",
                        problemEn = "'from' must not be later than 'to'.",
                        from = rangeStart,
                        to = rangeEnd,
                    });
                }

                var events = await CollectEventsAsync(db, rangeStart, rangeEnd, ct);

                var schedule = new CalendarScheduleDto(
                    rangeStart,
                    rangeEnd,
                    events
                        .GroupBy(e => e.Date)
                        .Select(group => new CalendarDayDto(
                            group.Key,
                            group.Select(e => e.ToItemDto()).ToList()))
                        .ToList());

                return Results.Ok(schedule);
            })
            .WithTags("Календарь / Calendar")
            .WithSummary("Расписания календаря")
            .WithDescription("Собирает автопроверки онгоингов, даты выхода серий и релизы тайтлов в планах в единый календарь.");

        group.MapGet("/calendar/ics", async (
                AppDbContext db,
                [FromQuery] DateOnly? from,
                [FromQuery] DateOnly? to,
                CancellationToken ct) =>
            {
                var today = DateOnly.FromDateTime(DateTime.UtcNow);
                var rangeStart = from ?? today.AddDays(-7);
                var rangeEnd = to ?? today.AddDays(90);

                if (rangeStart > rangeEnd)
                {
                    return Results.BadRequest(new
                    {
                        problem = "Диапазон дат некорректен: 'from' должна быть не позже 'to'.",
                        problemEn = "'from' must not be later than 'to'.",
                        from = rangeStart,
                        to = rangeEnd,
                    });
                }

                var events = await CollectEventsAsync(db, rangeStart, rangeEnd, ct);
                var ics = IcsBuilder.Build(events, DateTime.UtcNow);

                return Results.Bytes(
                    Encoding.UTF8.GetBytes(ics),
                    contentType: "text/calendar; charset=utf-8",
                    fileDownloadName: "tsundoku-releases.ics");
            })
            .WithTags("Календарь / Calendar")
            .WithSummary("Экспорт календаря в iCalendar")
            .WithDescription("Отдает события календаря (серии и релизы) в формате RFC 5545 для Apple Calendar, Google Calendar и Thunderbird.");

        group.MapGet("/calendar/backlog-deadlines", async (
                AppDbContext db,
                CancellationToken ct) =>
            {
                var today = DateOnly.FromDateTime(DateTime.UtcNow);
                var events = await CollectEventsAsync(db, today, today.AddDays(30), ct);

                var deadlines = new List<BacklogDeadlineDto>();

                // 1. Ongoings: the next episode airs while the user has not caught up to it yet.
                foreach (var e in events)
                {
                    if (e.Kind != "air_date") continue;

                    var watched = e.CurrentProgress ?? 0;
                    var target = (e.EpisodeNumber ?? 0) - 1;
                    if (target <= watched) continue;

                    deadlines.Add(new BacklogDeadlineDto(
                        e.MediaId, e.Title, e.Type, e.CoverUrl, "air_date", e.Date,
                        e.Date.DayNumber - today.DayNumber,
                        e.EpisodeNumber, e.SeasonNumber, target - watched,
                        null, null, null));
                }

                // 2. Franchise sequels: the next part releases soon while the previous one is unfinished.
                foreach (var e in events)
                {
                    if (e.Kind != "release" || e.FranchiseId is null) continue;

                    var blocker = await FindFranchiseBlockerAsync(db, e, ct);
                    if (blocker is not { } found) continue;

                    deadlines.Add(new BacklogDeadlineDto(
                        e.MediaId, e.Title, e.Type, e.CoverUrl, "release", e.Date,
                        e.Date.DayNumber - today.DayNumber,
                        null, null, null,
                        found.Title, found.Progress, found.TotalCount));
                }

                return Results.Ok(deadlines
                    .OrderBy(d => d.DeadlineDate)
                    .ThenBy(d => d.Title, StringComparer.Ordinal)
                    .ToList());
            })
            .WithTags("Календарь / Calendar")
            .WithSummary("Дедлайны по бэклогу")
            .WithDescription("Тайтлы с релизом в ближайшие 30 дней, к которым нужно успеть: отстающие онгоинги и сиквелы с незавершенной предыдущей частью франшизы.");

        group.MapPost("/{id:guid}/auto-refresh/trigger", async (
                Guid id,
                AppDbContext db,
                MetadataAggregatorService aggregator,
                [FromServices] ILoggerFactory loggerFactory,
                CancellationToken ct) =>
            {
                var item = await db.LoadMediaItemAsync(id, ct);

                if (item is null)
                {
                    return Results.NotFound();
                }

                await AutoRefreshRunner.RunAsync(db, aggregator, loggerFactory.CreateLogger("AutoRefresh"), item, ct);

                return Results.Ok(MediaDetailProjection.ToDetailDto(item));
            })
            .WithTags("Календарь / Calendar")
            .WithSummary("Принудительная автопроверка тайтла")
            .WithDescription("Немедленно опрашивает источники, подтягивает новые главы/серии, двигает интервал по правилам автофильтрации и возвращает обновлённый тайтл.");

        return app;
    }

    /// <summary>
    /// Gathers every dated event inside [rangeStart, rangeEnd]: scheduled auto-checks, episode air
    /// dates (with the show's aggregated progress) and planned releases. Shared by the JSON
    /// schedule, the .ics feed and the backlog widget so the three never disagree.
    /// </summary>
    private static async Task<List<CalendarEventRow>> CollectEventsAsync(
        AppDbContext db, DateOnly rangeStart, DateOnly rangeEnd, CancellationToken ct)
    {
        var events = new List<CalendarEventRow>();

        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        var windowStart = rangeStart.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
        var windowEnd = rangeEnd.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);

        // 1. Scheduled auto-refresh checks.
        // The bounds must be bound in the exact TEXT format Microsoft.Data.Sqlite
        // stores DateTime with ("yyyy-MM-dd HH:mm:ss.fffffff", space separator):
        // these comparisons are lexical, and "o"-format strings ("...T00:00...")
        // sort AFTER every same-day stored value, silently dropping events that
        // fall on the window's first day.
        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT * FROM MediaItems
            WHERE NextAutoRefreshAt IS NOT NULL
              AND NextAutoRefreshAt >= @start AND NextAutoRefreshAt <= @end
            ORDER BY NextAutoRefreshAt;
            """;
        cmd.Parameters.Add(new SqliteParameter("@start", windowStart.ToString("yyyy-MM-dd HH:mm:ss.fffffff")));
        cmd.Parameters.Add(new SqliteParameter("@end", windowEnd.ToString("yyyy-MM-dd HH:mm:ss.fffffff")));
        using (var reader = await cmd.ExecuteReaderAsync(ct))
        {
            while (await reader.ReadAsync(ct))
            {
                var item = AppDbContext.ReadMediaItemRow(reader).ToEntity();
                var nextAutoRefresh = reader.IsDBNull(reader.GetOrdinal("NextAutoRefreshAt"))
                    ? (DateTime?)null
                    : reader.GetDateTime(reader.GetOrdinal("NextAutoRefreshAt"));
                if (nextAutoRefresh is not { } dt) continue;

                events.Add(new CalendarEventRow(
                    DateOnly.FromDateTime(dt),
                    item.Id,
                    item.Title,
                    MediaResponseMapper.GetType(item),
                    item.CoverUrl,
                    item switch
                    {
                        Manga manga => manga.CurrentChapter,
                        Book book => book.CurrentPage,
                        TvShow show => show.TotalEpisodesWatched,
                        _ => null,
                    },
                    item switch
                    {
                        Manga manga => manga.TotalChapters,
                        TvShow show => show.TotalEpisodesCount,
                        _ => null,
                    },
                    Kind: "auto_refresh",
                    Details: $"Проверка обновлений (раз в {item.AutoRefreshIntervalDays} дн.)",
                    EpisodeNumber: null,
                    SeasonNumber: null,
                    IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true },
                    FranchiseId: item.FranchiseId,
                    FranchiseOrder: item.FranchiseOrder));
            }
        }

        // 2. Episodes with a precise air date, parsed out of the season's stored episode list.
        using var cmd2 = conn.CreateCommand();
        cmd2.CommandText = "SELECT * FROM MediaItems WHERE MediaType = 'TvShow';";
        using (var reader2 = await cmd2.ExecuteReaderAsync(ct))
        {
            while (await reader2.ReadAsync(ct))
            {
                var show = (TvShow)AppDbContext.ReadMediaItemRow(reader2).ToEntity();

                using var seasonsCmd = conn.CreateCommand();
                seasonsCmd.CommandText = """
                    SELECT SeasonNumber, CurrentEpisode, TotalEpisodes, EpisodesData
                    FROM TvSeasons WHERE TvShowId = @showId ORDER BY SeasonNumber;
                    """;
                seasonsCmd.Parameters.Add(new SqliteParameter("@showId", show.Id.ToString().ToUpperInvariant()));
                using var seasonsReader = await seasonsCmd.ExecuteReaderAsync(ct);

                var watchedTotal = 0;
                var totalCount = 0;
                while (await seasonsReader.ReadAsync(ct))
                {
                    watchedTotal += seasonsReader.GetInt32(seasonsReader.GetOrdinal("CurrentEpisode"));
                    totalCount += seasonsReader.GetInt32(seasonsReader.GetOrdinal("TotalEpisodes"));

                    var episodesData = seasonsReader.IsDBNull(seasonsReader.GetOrdinal("EpisodesData"))
                        ? null
                        : seasonsReader.GetString(seasonsReader.GetOrdinal("EpisodesData"));
                    if (episodesData is null) continue;

                    var seasonNumber = seasonsReader.GetInt32(seasonsReader.GetOrdinal("SeasonNumber"));
                    List<ExternalEpisodeDto>? episodes;
                    try
                    {
                        episodes = JsonSerializer.Deserialize(
                            episodesData,
                            (JsonTypeInfo<List<ExternalEpisodeDto>>)MediaRatingSerializer.ReadOptions.GetTypeInfo(typeof(List<ExternalEpisodeDto>)));
                    }
                    catch (JsonException)
                    {
                        continue;
                    }

                    if (episodes is null) continue;

                    foreach (var episode in episodes)
                    {
                        DateTime? airDate = DateTime.TryParse(episode.AirDate, out var parsed) ? parsed : null;
                        DateOnly? day = airDate is { } dt ? DateOnly.FromDateTime(dt) : null;
                        if (day is null || day < rangeStart || day > rangeEnd)
                        {
                            continue;
                        }

                        events.Add(new CalendarEventRow(
                            day.Value,
                            show.Id,
                            show.Title,
                            "tvshow",
                            show.CoverUrl,
                            watchedTotal,
                            totalCount > 0 ? totalCount : null,
                            Kind: "air_date",
                            Details: $"S{seasonNumber} E{episode.Number}",
                            EpisodeNumber: episode.Number,
                            SeasonNumber: seasonNumber,
                            IsAnime: show.IsAnime,
                            FranchiseId: show.FranchiseId,
                            FranchiseOrder: show.FranchiseOrder));
                    }
                }
            }
        }

        // 3. Planned titles whose release date lands inside the window.
        using var cmd3 = conn.CreateCommand();
        cmd3.CommandText = """
            SELECT * FROM MediaItems
            WHERE Status = @planned
              AND ReleaseDate IS NOT NULL
              AND ReleaseDate >= @start AND ReleaseDate <= @end;
            """;
        // A local prevents the constant-0 overload trap: `new SqliteParameter(name, (int)X)`
        // with X==0 binds to the (string, SqliteType) ctor, leaving Value null.
        var plannedStatus = (int)MediaStatus.Planned;
        cmd3.Parameters.Add(new SqliteParameter("@planned", plannedStatus));
        cmd3.Parameters.Add(new SqliteParameter("@start", windowStart.ToString("yyyy-MM-dd HH:mm:ss.fffffff")));
        cmd3.Parameters.Add(new SqliteParameter("@end", windowEnd.ToString("yyyy-MM-dd HH:mm:ss.fffffff")));
        using (var reader3 = await cmd3.ExecuteReaderAsync(ct))
        {
            while (await reader3.ReadAsync(ct))
            {
                var item = AppDbContext.ReadMediaItemRow(reader3).ToEntity();
                var releaseDate = reader3.IsDBNull(reader3.GetOrdinal("ReleaseDate"))
                    ? (DateTime?)null
                    : reader3.GetDateTime(reader3.GetOrdinal("ReleaseDate"));
                if (releaseDate is not { } rd) continue;

                events.Add(new CalendarEventRow(
                    DateOnly.FromDateTime(rd),
                    item.Id,
                    item.Title,
                    MediaResponseMapper.GetType(item),
                    item.CoverUrl,
                    null,
                    null,
                    Kind: "release",
                    Details: "Релиз",
                    EpisodeNumber: null,
                    SeasonNumber: null,
                    IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true },
                    FranchiseId: item.FranchiseId,
                    FranchiseOrder: item.FranchiseOrder));
            }
        }

        return events
            .OrderBy(e => e.Date)
            .ThenBy(e => e.Kind, StringComparer.Ordinal)
            .ThenBy(e => e.Details, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>
    /// For an upcoming release, the nearest previous franchise part the user has not finished yet.
    /// Returns null when every earlier part is completed/dropped/on hold or no ordering is known.
    /// </summary>
    private static async Task<(string Title, int? Progress, int? TotalCount)?> FindFranchiseBlockerAsync(
        AppDbContext db, CalendarEventRow upcoming, CancellationToken ct)
    {
        var conn = db.Connection;
        if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM MediaItems WHERE FranchiseId = @fid;";
        cmd.Parameters.Add(new SqliteParameter("@fid", upcoming.FranchiseId!.Value.ToString().ToUpperInvariant()));
        using var reader = await cmd.ExecuteReaderAsync(ct);

        MediaItem? blocker = null;
        while (await reader.ReadAsync(ct))
        {
            var candidate = AppDbContext.ReadMediaItemRow(reader).ToEntity();
            if (candidate.Id == upcoming.MediaId) continue;
            if (candidate.Status is not (MediaStatus.Planned or MediaStatus.InProgress)) continue;
            if (upcoming.FranchiseOrder is { } upcomingOrder
                && (candidate.FranchiseOrder ?? -1) >= upcomingOrder)
            {
                continue;
            }

            if (blocker is null || (candidate.FranchiseOrder ?? -1) > (blocker.FranchiseOrder ?? -1))
            {
                blocker = candidate;
            }
        }

        if (blocker is null) return null;

        var progress = blocker switch
        {
            Manga manga => manga.CurrentChapter,
            Book book => book.CurrentPage,
            VideoGame game => game.HoursPlayed,
            _ => 0,
        };
        var total = blocker switch
        {
            Manga manga => manga.TotalChapters,
            Book book => book.TotalPages > 0 ? book.TotalPages : null,
            _ => null,
        };

        // A show's counters are computed from its seasons, which the flat row does not carry.
        if (blocker is TvShow show)
        {
            show.Seasons = await AppDbContext.LoadTvSeasons(conn, show.Id.ToString().ToUpperInvariant(), ct);
            progress = show.TotalEpisodesWatched;
            total = show.TotalEpisodesCount > 0 ? show.TotalEpisodesCount : null;
        }

        return (blocker.Title, progress > 0 ? progress : null, total);
    }

    /// <summary>Renders the collected events as an RFC 5545 VCALENDAR document.</summary>
    private static class IcsBuilder
    {
        public static string Build(IReadOnlyList<CalendarEventRow> events, DateTime generatedAtUtc)
        {
            var sb = new StringBuilder();
            AppendLine(sb, "BEGIN:VCALENDAR");
            AppendLine(sb, "VERSION:2.0");
            AppendLine(sb, "PRODID:-//Tsundoku//MediaTracker//RU");
            AppendLine(sb, "CALSCALE:GREGORIAN");
            AppendLine(sb, "X-WR-CALNAME:Tsundoku — Календарь релизов");

            foreach (var e in events)
            {
                if (e.Kind is not ("air_date" or "release")) continue;

                var dateStamp = e.Date.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
                var summary = e.Kind == "release"
                    ? $"🎬 Премьера: {e.Title}"
                    : $"📺 {e.Title} — S{e.SeasonNumber ?? 0}E{e.EpisodeNumber ?? 0}";

                AppendLine(sb, "BEGIN:VEVENT");
                AppendLine(sb, $"UID:{e.MediaId.ToString("D")}-{e.Kind}-{dateStamp}-{e.EpisodeNumber ?? 0}@tsundoku.local");
                AppendLine(sb, $"DTSTAMP:{generatedAtUtc:yyyyMMdd'T'HHmmss'Z'}");
                AppendLine(sb, $"DTSTART;VALUE=DATE:{dateStamp}");
                AppendLine(sb, $"SUMMARY:{EscapeText(summary)}");
                AppendLine(sb, $"DESCRIPTION:{EscapeText(BuildDescription(e))}");
                AppendLine(sb, "END:VEVENT");
            }

            AppendLine(sb, "END:VCALENDAR");
            return sb.ToString();
        }

        private static string BuildDescription(CalendarEventRow e)
        {
            var typeLabel = (e.IsAnime, e.Type) switch
            {
                (true, "tvshow") or (true, "movie") => "аниме",
                (_, "tvshow") => "сериал",
                (_, "movie") => "фильм",
                (_, "manga") => "манга",
                (_, "book") => "книга",
                (_, "game") => "игра",
                _ => e.Type,
            };

            var sb = new StringBuilder("Тип: ");
            sb.Append(typeLabel);

            if (e.CurrentProgress is { } progress)
            {
                var unit = e.Type switch
                {
                    "manga" => " гл.",
                    "book" => " стр.",
                    "tvshow" => " сер.",
                    _ => "",
                };
                sb.Append(" · Прогресс: ").Append(progress);
                if (e.TotalCount is > 0)
                {
                    sb.Append(" / ").Append(e.TotalCount.Value);
                }
                sb.Append(unit);
            }

            if (e.SeasonNumber is { } season && e.EpisodeNumber is { } episode)
            {
                sb.Append(" · Серия: S").Append(season).Append('E').Append(episode);
            }

            return sb.ToString();
        }

        private static string EscapeText(string value) => value
            .Replace("\\", "\\\\")
            .Replace(";", "\\;")
            .Replace(",", "\\,")
            .Replace("\r\n", "\\n")
            .Replace("\n", "\\n")
            .Replace("\r", "\\n");

        private static void AppendLine(StringBuilder sb, string line)
        {
            foreach (var chunk in Fold(line))
            {
                sb.Append(chunk).Append("\r\n");
            }
        }

        /// <summary>RFC 5545 §3.1: lines longer than 75 octets fold with a leading space on continuations.</summary>
        private static List<string> Fold(string line)
        {
            const int maxOctets = 75;
            if (Encoding.UTF8.GetByteCount(line) <= maxOctets)
            {
                return [line];
            }

            var chunks = new List<string>();
            var start = 0;
            var first = true;
            while (start < line.Length)
            {
                var limit = first ? maxOctets : maxOctets - 1;
                var octets = 0;
                var end = start;
                while (end < line.Length)
                {
                    // Surrogate pairs travel together: splitting one breaks UTF-8 for the whole line.
                    var size = char.IsHighSurrogate(line[end]) && end + 1 < line.Length
                        ? 4
                        : line[end] < 0x80 ? 1 : line[end] < 0x800 ? 2 : 3;
                    if (octets + size > limit) break;
                    octets += size;
                    end += char.IsHighSurrogate(line[end]) && end + 1 < line.Length ? 2 : 1;
                }

                if (end == start) end = start + 1;
                var chunk = line[start..end];
                chunks.Add(first ? chunk : " " + chunk);
                start = end;
                first = false;
            }

            return chunks;
        }
    }
}
