using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>
/// Pure calculator of the taste profile psychological analytics shown on the Stats "Taste Profile" tab.
/// Persona icon doubles as a stable identifier: the UI resolves titles, descriptions and traits via i18n.
/// </summary>
public static class TasteProfileCalculator
{
    public const string CacheKey = "stats:taste_profile";

    private static readonly string[] EraKeys = ["pre-1980", "1980s", "1990s", "2000s", "2010s", "2020s"];

    public static TasteProfileDto Calculate(
        IReadOnlyCollection<MediaItem> items,
        AdvancedStatsDto advancedStats,
        double bookPageMinutes = 1.5,
        double mangaChapterMinutes = 6.0)
    {
        var genreItems = BuildGenreIndex(items);

        return new TasteProfileDto
        {
            Persona = BuildPersona(items, advancedStats, genreItems),
            SunkCost = CalculateSunkCost(items, advancedStats, bookPageMinutes, mangaChapterMinutes),
            Divergence = CalculateDivergence(items),
            GenreParadox = BuildGenreParadox(genreItems),
            EraAffinity = BuildEraAffinity(items),
            GenreRadar = BuildGenreRadar(genreItems),
            DropAnalytics = CalculateDropAnalytics(items),
        };
    }

    private static Dictionary<string, List<MediaItem>> BuildGenreIndex(IReadOnlyCollection<MediaItem> items)
    {
        var genreItems = new Dictionary<string, List<MediaItem>>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in items)
        {
            if (string.IsNullOrWhiteSpace(item.Genres))
            {
                continue;
            }

            foreach (var rawGenre in item.Genres.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                var genre = GenreNormalizer.Normalize(rawGenre);
                if (string.IsNullOrWhiteSpace(genre))
                {
                    continue;
                }

                if (!genreItems.TryGetValue(genre, out var tracked))
                {
                    tracked = [];
                    genreItems[genre] = tracked;
                }

                tracked.Add(item);
            }
        }

        return genreItems;
    }

    /// <summary>"Lost time syndrome": hours sunk into titles rated ≤5 or dropped outright.</summary>
    private static SunkCostDto CalculateSunkCost(
        IReadOnlyCollection<MediaItem> items,
        AdvancedStatsDto advancedStats,
        double bookPageMinutes,
        double mangaChapterMinutes)
    {
        var lowScoreItems = items
            .Where(item => (item.Score.HasValue && item.Score.Value <= 5) || item.Status == MediaStatus.Dropped)
            .ToList();

        var breakdown = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        double lowScoreHours = 0;
        foreach (var item in lowScoreItems)
        {
            var hours = CalculateItemHours(item, bookPageMinutes, mangaChapterMinutes);
            lowScoreHours += hours;
            var type = AdvancedStatsCalculator.GetMediaTypeName(item);
            breakdown[type] = breakdown.GetValueOrDefault(type) + hours;
        }

        var percentage = advancedStats.TotalHours > 0
            ? Math.Round(lowScoreHours / advancedStats.TotalHours * 100.0, 1, MidpointRounding.AwayFromZero)
            : 0.0;

        return new SunkCostDto(
            Math.Round(lowScoreHours, 1, MidpointRounding.AwayFromZero),
            percentage,
            lowScoreItems.Count,
            breakdown
                .Where(kv => kv.Value > 0)
                .ToDictionary(kv => kv.Key, kv => Math.Round(kv.Value, 1, MidpointRounding.AwayFromZero)));
    }

    // Mirrors the AdvancedStatsCalculator hour formulas so the sunk cost share is consistent with
    // the totals shown on the "Summary" tab: games (raw hours unless planned), movies (duration with
    // a 90-minute fallback once completed), shows (watched episodes × episode duration, 24/45-minute
    // fallbacks), books (pages × page minutes) and manga (chapters × chapter minutes / volume ≈ 50 min).
    private static double CalculateItemHours(MediaItem item, double bookPageMinutes, double mangaChapterMinutes) => item switch
    {
        VideoGame game => game.Status == MediaStatus.Planned ? 0 : game.HoursPlayed ?? 0,
        Movie movie => movie.Status == MediaStatus.Completed
            ? (movie.DurationMinutes > 0 ? movie.DurationMinutes : 90) / 60.0
            : 0,
        TvShow show => CalculateShowHours(show),
        Book book => book.Status == MediaStatus.Planned
            ? 0
            : CalculateBookPages(book) * bookPageMinutes / 60.0,
        Manga manga => CalculateMangaChapters(manga, mangaChapterMinutes),
        _ => 0,
    };

    private static double CalculateShowHours(TvShow show)
    {
        var episodesWatched = show.Status == MediaStatus.Planned ? 0 : show.TotalEpisodesWatched;
        if (show.Status == MediaStatus.Completed && episodesWatched == 0)
        {
            episodesWatched = show.TotalEpisodesCount;
        }

        var duration = show.EpisodeDurationMinutes is > 0 ? show.EpisodeDurationMinutes.Value : show.IsAnime ? 24 : 45;
        return episodesWatched * duration / 60.0;
    }

    private static double CalculateBookPages(Book book) => book.Status == MediaStatus.Completed
        ? book.TotalPages > 0
            ? book.TotalPages
            : book.CurrentPage > 0 ? book.CurrentPage : 300
        : book.CurrentPage;

    private static double CalculateMangaChapters(Manga manga, double mangaChapterMinutes)
    {
        if (manga.Status == MediaStatus.Planned)
        {
            return 0;
        }

        if (manga.Status == MediaStatus.Completed)
        {
            return manga.TotalChapters is > 0
                ? manga.TotalChapters.Value * mangaChapterMinutes / 60.0
                : manga.TotalVolumes is > 0 ? manga.TotalVolumes.Value * 50.0 / 60.0 : 0;
        }

        return manga.CurrentChapter > 0
            ? manga.CurrentChapter * mangaChapterMinutes / 60.0
            : manga.CurrentVolume > 0 ? manga.CurrentVolume * 50.0 / 60.0 : 0;
    }

    /// <summary>"Me against the world": the biggest positive and negative gaps between the user's score and the world rating.</summary>
    private static CriticalDivergenceDto CalculateDivergence(IReadOnlyCollection<MediaItem> items)
    {
        var scored = items
            .Where(item => item.Score is >= 1 && item.ExternalRating is > 0)
            .Select(item => new
            {
                Item = item,
                UserScore = (double)item.Score!.Value,
                WorldRating = (double)item.ExternalRating!.Value,
                Delta = Math.Round(item.Score.Value - item.ExternalRating.Value, 1, MidpointRounding.AwayFromZero),
            })
            .ToList();

        // Hidden gem: my score is higher than the world's and mine deserved it (8+).
        var gem = scored
            .Where(x => x.UserScore >= 8)
            .OrderByDescending(x => x.Delta)
            .Select(x => ToDivergenceItem(x.Item, x.UserScore, x.WorldRating, x.Delta))
            .FirstOrDefault();

        // Disappointment: the world loved it (7.5+), I couldn't stand it (5 or lower).
        var disappointment = scored
            .Where(x => x.WorldRating >= 7.5 && x.UserScore <= 5)
            .OrderByDescending(x => x.WorldRating - x.UserScore)
            .Select(x => ToDivergenceItem(
                x.Item,
                x.UserScore,
                x.WorldRating,
                Math.Round(x.UserScore - x.WorldRating, 1, MidpointRounding.AwayFromZero)))
            .FirstOrDefault();

        return new CriticalDivergenceDto(gem, disappointment);
    }

    private static DivergenceItemDto ToDivergenceItem(MediaItem item, double userScore, double worldRating, double delta) => new(
        item.Id,
        item.Title,
        AdvancedStatsCalculator.GetMediaTypeName(item),
        item.CoverUrl,
        Math.Round(userScore, 1, MidpointRounding.AwayFromZero),
        Math.Round(worldRating, 1, MidpointRounding.AwayFromZero),
        delta);

    /// <summary>"Genre paradox": where the user finishes nearly everything and where they abandon ship.</summary>
    private static List<GenreCompletionStatDto> BuildGenreParadox(Dictionary<string, List<MediaItem>> genreItems) => genreItems
        .Select(kv =>
        {
            var tracked = kv.Value.Where(item => item.Status != MediaStatus.Planned).ToList();
            return new
            {
                Genre = kv.Key,
                TrackedCount = tracked.Count,
                Completed = tracked.Count(item => item.Status == MediaStatus.Completed),
                Dropped = tracked.Count(item => item.Status == MediaStatus.Dropped),
            };
        })
        .Where(x => x.TrackedCount >= 2)
        .OrderByDescending(x => x.TrackedCount)
        .ThenBy(x => x.Genre, StringComparer.OrdinalIgnoreCase)
        .Take(6)
        .Select(x => new GenreCompletionStatDto(
            x.Genre,
            x.TrackedCount,
            x.Completed,
            x.Dropped,
            Math.Round((double)x.Completed / x.TrackedCount * 100.0, 1, MidpointRounding.AwayFromZero),
            Math.Round((double)x.Dropped / x.TrackedCount * 100.0, 1, MidpointRounding.AwayFromZero)))
        .ToList();

    /// <summary>"Golden era": decades of the user's favorite titles (rated 8+ or completed).</summary>
    private static List<EraAffinityStatDto> BuildEraAffinity(IReadOnlyCollection<MediaItem> items)
    {
        var favorites = items.Where(item => item.Score >= 8 || item.Status == MediaStatus.Completed);
        var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var total = 0;
        foreach (var item in favorites)
        {
            var era = GetEra(item.ReleaseYear ?? item.ReleaseDate?.Year);
            if (era is null)
            {
                continue;
            }

            counts[era] = counts.GetValueOrDefault(era) + 1;
            total++;
        }

        return EraKeys
            .Where(counts.ContainsKey)
            .Select(key => new EraAffinityStatDto(
                key,
                counts[key],
                total > 0 ? Math.Round(counts[key] / (double)total * 100.0, 1, MidpointRounding.AwayFromZero) : 0.0))
            .ToList();
    }

    private static string? GetEra(int? year) => year switch
    {
        null => null,
        < 1980 => "pre-1980",
        < 1990 => "1980s",
        < 2000 => "1990s",
        < 2010 => "2000s",
        < 2020 => "2010s",
        _ => "2020s",
    };

    /// <summary>Taste radar: the six dominant genres with a normalized volume share and the average personal score.</summary>
    private static List<RadarAxisDto> BuildGenreRadar(Dictionary<string, List<MediaItem>> genreItems)
    {
        var axes = genreItems
            .Select(kv => new { Genre = kv.Key, Count = kv.Value.Count, Average = CalculateAverageScore(kv.Value) })
            .OrderByDescending(x => x.Count)
            .ThenBy(x => x.Genre, StringComparer.OrdinalIgnoreCase)
            .Take(6)
            .ToList();

        var maxCount = axes.Count > 0 ? axes.Max(x => x.Count) : 0;
        return axes
            .Select(x => new RadarAxisDto(
                x.Genre,
                maxCount > 0 ? Math.Round(x.Count / (double)maxCount * 100.0, 1, MidpointRounding.AwayFromZero) : 0.0,
                x.Average))
            .ToList();
    }

    private static double CalculateAverageScore(List<MediaItem> items)
    {
        var scores = items.Select(item => item.Score).Where(score => score is >= 1).ToList();
        return scores.Count > 0
            ? Math.Round(scores.Average(score => score!.Value), 1, MidpointRounding.AwayFromZero)
            : 0.0;
    }

    private static TastePersonaDto BuildPersona(
        IReadOnlyCollection<MediaItem> items,
        AdvancedStatsDto advancedStats,
        Dictionary<string, List<MediaItem>> genreItems)
    {
        var activeTypes = items
            .Select(AdvancedStatsCalculator.GetMediaTypeName)
            .Where(type => type != "other")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();
        var leadingGenre = genreItems
            .OrderByDescending(kv => kv.Value.Count)
            .ThenBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault().Key;

        // Deterministic ladder: strictness first, then discipline, focus, genre identity, breadth.
        if (advancedStats.AverageScore < 6.8 && advancedStats.TotalTitles >= 5)
        {
            return new TastePersonaDto(
                "Strict Critic",
                "You hold your library to sky-high standards: few titles manage to impress you, and even the world's favorites earn a skeptical squint. Your shelf is a courtroom — and most defendants leave with a verdict below seven.",
                "critic",
                ["high_standards", "honest_reviews"]);
        }

        if (advancedStats.CompletionRatePercent >= 75 && advancedStats.TotalTitles >= 10)
        {
            return new TastePersonaDto(
                "Perfectionist Completer",
                "You never leave a story half-read: if you start something, you finish it. Dropping a title is a defeat you almost never allow yourself, and your tracked progress bars are a monument to discipline.",
                "perfectionist",
                ["finisher", "no_dnf"]);
        }

        if (advancedStats.AnimeHours + advancedStats.MangaHours > advancedStats.TotalHours * 0.6)
        {
            return new TastePersonaDto(
                "Otaku Explorer",
                "Anime and manga clearly dominate your hours: you drift between studios and manga magazines faster than between shelves and streaming services. Your taste map is drawn by voice actors, opening songs and chapter cliffhangers.",
                "otaku",
                ["anime_focus", "deep_dive"]);
        }

        if (leadingGenre is "Sci-Fi" or "Cyberpunk")
        {
            return new TastePersonaDto(
                "Futurist Visionary",
                "Science fiction and cyberpunk lead your collection: you gravitate to worlds where megacorporations, starships and shortcomings of human nature collide. Your favorite question is \"and what happens next?\"",
                "visionary",
                ["sci_fi_lead"]);
        }

        if (activeTypes >= 4)
        {
            return new TastePersonaDto(
                "Cultural Omnivore",
                "You taste everything the culture industry serves: games, cinema, series, books and manga share your evenings evenly, and no single art form holds center stage for long. Every format gets its chance, and few are wasted on you.",
                "omnivore",
                ["all_formats", "no_limits"]);
        }

        return new TastePersonaDto(
            "Thoughtful Archivist",
            "You move at your own pace: slower, deeper, without chasing hype. Your library grows drop by drop, which means every title you own was chosen consciously.",
            "archivist",
            ["mindful_pace", "depth_first"]);
    }

    private static DropAnalyticsDto CalculateDropAnalytics(IReadOnlyCollection<MediaItem> items)
    {
        var droppedItems = items
            .Where(item => item.Status == MediaStatus.Dropped)
            .ToList();

        if (droppedItems.Count == 0)
        {
            return new DropAnalyticsDto(
                TotalDropped: 0,
                AverageDropProgressPercent: 0.0,
                EarlyDropCount: 0,
                MidDropCount: 0,
                LateDropCount: 0,
                TopReasons: []);
        }

        int earlyCount = 0;
        int midCount = 0;
        int lateCount = 0;
        double progressSum = 0;

        foreach (var item in droppedItems)
        {
            var progress = CalculateItemProgressPercent(item);
            progressSum += progress;

            if (progress < 20.0)
            {
                earlyCount++;
            }
            else if (progress <= 70.0)
            {
                midCount++;
            }
            else
            {
                lateCount++;
            }
        }

        var avgProgress = Math.Round(progressSum / droppedItems.Count, 1, MidpointRounding.AwayFromZero);

        var topReasons = droppedItems
            .GroupBy(item => string.IsNullOrWhiteSpace(item.DropReason) ? "unspecified" : item.DropReason.Trim())
            .Select(g =>
            {
                var count = g.Count();
                var percentage = Math.Round((double)count / droppedItems.Count * 100.0, 1, MidpointRounding.AwayFromZero);
                return new DropReasonStatDto(g.Key, count, percentage);
            })
            .OrderByDescending(r => r.Count)
            .ThenBy(r => r.Reason, StringComparer.OrdinalIgnoreCase)
            .ToList();

        return new DropAnalyticsDto(
            TotalDropped: droppedItems.Count,
            AverageDropProgressPercent: avgProgress,
            EarlyDropCount: earlyCount,
            MidDropCount: midCount,
            LateDropCount: lateCount,
            TopReasons: topReasons);
    }

    private static double CalculateItemProgressPercent(MediaItem item) => item switch
    {
        Book book => book.TotalPages > 0
            ? Math.Clamp((double)book.CurrentPage / book.TotalPages * 100.0, 0.0, 100.0)
            : 0.0,
        Manga manga => manga.TotalChapters is > 0
            ? Math.Clamp((double)manga.CurrentChapter / manga.TotalChapters.Value * 100.0, 0.0, 100.0)
            : 0.0,
        TvShow show => show.TotalEpisodesCount > 0
            ? Math.Clamp((double)show.TotalEpisodesWatched / show.TotalEpisodesCount * 100.0, 0.0, 100.0)
            : 0.0,
        _ => 0.0,
    };
}
