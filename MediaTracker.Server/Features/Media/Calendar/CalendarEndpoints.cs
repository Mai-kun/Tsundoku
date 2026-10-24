using System.Text.Json;
using MediaTracker.Server.Domain.Entities;
using MediaTracker.Server.Domain.Enums;
using MediaTracker.Server.Domain.Rules;
using MediaTracker.Server.Features.External.RefreshMetadata;
using MediaTracker.Server.Features.Jobs;
using MediaTracker.Server.Features.Media.MediaContract;
using MediaTracker.Server.Infrastructure.ExternalApis;
using MediaTracker.Server.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

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

                // 1. Scheduled auto-refresh checks: the date is the poll itself, not real content.
                var windowStart = rangeStart.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc);
                var windowEnd = rangeEnd.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc);
                var scheduled = await db.MediaItems
                    .Where(m => m.NextAutoRefreshAt != null
                             && m.NextAutoRefreshAt >= windowStart
                             && m.NextAutoRefreshAt <= windowEnd)
                    .OrderBy(m => m.NextAutoRefreshAt)
                    .ToListAsync(ct);

                items.AddRange(scheduled.Select(item => (
                    Date: DateOnly.FromDateTime(item.NextAutoRefreshAt!.Value),
                    Item: new CalendarItemDto(
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
                        IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true }))));

                // 2. Episodes with a precise air date, parsed out of the season's stored episode list.
                var shows = await db.TvShows
                    .Include(show => show.Seasons)
                    .Where(show => show.Seasons.Any(season => season.EpisodesData != null))
                    .ToListAsync(ct);

                foreach (var show in shows)
                {
                    var watched = show.Seasons.Sum(season => season.CurrentEpisode);
                    var total = show.TotalEpisodesCount;

                    foreach (var season in show.Seasons.Where(season => season.EpisodesData != null))
                    {
                        List<ExternalEpisodeDto>? episodes;
                        try
                        {
                            episodes = JsonSerializer.Deserialize<List<ExternalEpisodeDto>>(
                                season.EpisodesData ?? "[]",
                                MediaRatingSerializer.ReadOptions);
                        }
                        catch (JsonException)
                        {
                            continue;
                        }

                        if (episodes is null)
                        {
                            continue;
                        }

                        foreach (var episode in episodes)
                        {
                            DateTime? airDate = DateTime.TryParse(episode.AirDate, out var parsed) ? parsed : null;
                            DateOnly? day = airDate is { } dt ? DateOnly.FromDateTime(dt) : null;
                            if (day is null || day < rangeStart || day > rangeEnd)
                            {
                                continue;
                            }

                            items.Add((
                                day.Value,
                                new CalendarItemDto(
                                    show.Id,
                                    show.Title,
                                    "tvshow",
                                    show.CoverUrl,
                                    watched,
                                    total,
                                    Kind: "air_date",
                                    Details: $"S{season.SeasonNumber} E{episode.Number}",
                                    EpisodeNumber: episode.Number,
                                    SeasonNumber: season.SeasonNumber,
                                    IsAnime: show.IsAnime)));
                        }
                    }
                }

                // 3. Planned titles whose release date lands inside the window.
                var upcoming = await db.MediaItems
                    .Where(m => m.Status == MediaStatus.Planned
                             && m.ReleaseDate != null
                             && m.ReleaseDate >= windowStart
                             && m.ReleaseDate <= windowEnd)
                    .ToListAsync(ct);

                items.AddRange(upcoming.Select(item => (
                    Date: DateOnly.FromDateTime(item.ReleaseDate!.Value),
                    Item: new CalendarItemDto(
                        item.Id,
                        item.Title,
                        MediaResponseMapper.GetType(item),
                        item.CoverUrl,
                        CurrentProgress: null,
                        TotalCount: null,
                        Kind: "release",
                        Details: "Релиз",
                        EpisodeNumber: null,
                        SeasonNumber: null,
                        IsAnime: item is TvShow { IsAnime: true } or Movie { IsAnime: true }))));

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
                var item = await db.MediaItems
                    .Include(media => (media as TvShow)!.Seasons)
                    .Include(media => (media as Manga)!.Volumes)
                    .AsSplitQuery()
                    .SingleOrDefaultAsync(media => media.Id == id, ct);

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
