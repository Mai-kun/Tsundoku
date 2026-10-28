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

                var items = new List<(DateOnly Date, CalendarItemDto Item)>();

                var conn = db.Connection;
                if (conn.State != global::System.Data.ConnectionState.Open) await conn.OpenAsync(ct);

                // 1. Scheduled auto-refresh checks.
                var windowStart = rangeStart.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
                var windowEnd = rangeEnd.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);

                using var cmd = conn.CreateCommand();
                cmd.CommandText = """
                    SELECT * FROM MediaItems
                    WHERE NextAutoRefreshAt IS NOT NULL
                      AND NextAutoRefreshAt >= @start AND NextAutoRefreshAt <= @end
                    ORDER BY NextAutoRefreshAt;
                    """;
                cmd.Parameters.Add(new SqliteParameter("@start", windowStart.ToString("o")));
                cmd.Parameters.Add(new SqliteParameter("@end", windowEnd.ToString("o")));
                using var reader = await cmd.ExecuteReaderAsync(ct);
                while (await reader.ReadAsync(ct))
                {
                    var row = AppDbContext.ReadMediaItemRow(reader);
                    var item = row.ToEntity();
                    var nextAutoRefresh = reader.IsDBNull(reader.GetOrdinal("NextAutoRefreshAt")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("NextAutoRefreshAt"));
                    if (nextAutoRefresh is not { } dt) continue;

                    items.Add((DateOnly.FromDateTime(dt), new CalendarItemDto(
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
                        IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true })));
                }

                // 2. Episodes with a precise air date, parsed out of the season's stored episode list.
                using var cmd2 = conn.CreateCommand();
                cmd2.CommandText = "SELECT Id, Title, CoverUrl FROM MediaItems WHERE MediaType = 'TvShow';";
                using var reader2 = await cmd2.ExecuteReaderAsync(ct);
                while (await reader2.ReadAsync(ct))
                {
                    var showId = Guid.Parse(reader2.GetString(reader2.GetOrdinal("Id")));
                    var showTitle = reader2.GetString(reader2.GetOrdinal("Title"));
                    var showCoverUrl = reader2.IsDBNull(reader2.GetOrdinal("CoverUrl")) ? null : reader2.GetString(reader2.GetOrdinal("CoverUrl"));

                    using var seasonsCmd = conn.CreateCommand();
                    seasonsCmd.CommandText = "SELECT * FROM TvSeasons WHERE TvShowId = @showId AND EpisodesData IS NOT NULL;";
                    seasonsCmd.Parameters.Add(new SqliteParameter("@showId", showId.ToString().ToUpperInvariant()));
                    using var seasonsReader = await seasonsCmd.ExecuteReaderAsync(ct);
                    while (await seasonsReader.ReadAsync(ct))
                    {
                        var seasonNumber = seasonsReader.GetInt32(seasonsReader.GetOrdinal("SeasonNumber"));
                        var episodesData = seasonsReader.IsDBNull(seasonsReader.GetOrdinal("EpisodesData")) ? null : seasonsReader.GetString(seasonsReader.GetOrdinal("EpisodesData"));
                        if (episodesData is null) continue;

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

                            items.Add((day.Value, new CalendarItemDto(
                                showId,
                                showTitle,
                                "tvshow",
                                showCoverUrl,
                                null,
                                null,
                                Kind: "air_date",
                                Details: $"S{seasonNumber} E{episode.Number}",
                                EpisodeNumber: episode.Number,
                                SeasonNumber: seasonNumber,
                                IsAnime: false)));
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
                cmd3.Parameters.Add(new SqliteParameter("@start", windowStart.ToString("o")));
                cmd3.Parameters.Add(new SqliteParameter("@end", windowEnd.ToString("o")));
                using var reader3 = await cmd3.ExecuteReaderAsync(ct);
                while (await reader3.ReadAsync(ct))
                {
                    var row = AppDbContext.ReadMediaItemRow(reader3);
                    var item = row.ToEntity();
                    var releaseDate = reader3.IsDBNull(reader3.GetOrdinal("ReleaseDate")) ? (DateTime?)null : reader3.GetDateTime(reader3.GetOrdinal("ReleaseDate"));
                    if (releaseDate is not { } rd) continue;

                    items.Add((DateOnly.FromDateTime(rd), new CalendarItemDto(
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
                        IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true })));
                }

                var schedule = new CalendarScheduleDto(
                    rangeStart,
                    rangeEnd,
                    items
                        .GroupBy(pair => pair.Date)
                        .Select(group => new CalendarDayDto(
                            group.Key,
                            group.Select(pair => pair.Item)
                                .OrderBy(item => item.Kind, StringComparer.Ordinal)
                                .ThenBy(item => item.Details, StringComparer.Ordinal)
                                .ToList()))
                        .OrderBy(day => day.Date)
                        .ToList());

                return Results.Ok(schedule);
            })
            .WithTags("Календарь / Calendar")
            .WithSummary("Расписания календаря")
            .WithDescription("Собирает автопроверки онгоингов, даты выхода серий и релизы тайтлов в планах в единый календарь.");

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
}
