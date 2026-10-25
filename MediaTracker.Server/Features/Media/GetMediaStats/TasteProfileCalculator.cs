using MediaTracker.Server.Domain.Entities;

namespace MediaTracker.Server.Features.Media.GetMediaStats;

/// <summary>
/// Pure calculator of the taste profile psychological analytics shown on the Stats "Taste Profile" tab.
/// Persona icon doubles as a stable identifier: the UI resolves titles, descriptions and traits via i18n.
/// </summary>
public static class TasteProfileCalculator
{
    public const string CacheKey = "stats:taste_profile";
    public const string CacheKeyCompleted = "stats:taste_profile:completed";
    public const string CacheKeyAll = "stats:taste_profile:all";

    public static void InvalidateCache(Microsoft.Extensions.Caching.Memory.IMemoryCache? cache)
    {
        if (cache is null) return;
        cache.Remove(CacheKey);
        cache.Remove(CacheKeyCompleted);
        cache.Remove(CacheKeyAll);
    }

    private static readonly string[] EraKeys = ["pre-1980", "1980s", "1990s", "2000s", "2010s", "2020s"];

    public static TasteProfileDto Calculate(
        IReadOnlyCollection<MediaItem> items,
        AdvancedStatsDto advancedStats,
        double bookPageMinutes = 1.5,
        double mangaChapterMinutes = 6.0,
        bool onlyCompleted = true)
    {
        var genreItems = BuildGenreIndex(items, onlyCompleted);
        var allTrackedGenreItems = BuildGenreIndex(items, onlyCompleted: false);

        return new TasteProfileDto
        {
            Persona = BuildPersona(items, advancedStats, genreItems, onlyCompleted),
            SunkCost = CalculateSunkCost(items, advancedStats, bookPageMinutes, mangaChapterMinutes, onlyCompleted),
            Divergence = CalculateDivergence(items, onlyCompleted),
            GenreParadox = BuildGenreParadox(allTrackedGenreItems),
            EraAffinity = BuildEraAffinity(items, onlyCompleted),
            GenreRadar = BuildGenreRadar(genreItems),
            DropAnalytics = CalculateDropAnalytics(items),
        };
    }

    private static Dictionary<string, List<MediaItem>> BuildGenreIndex(IReadOnlyCollection<MediaItem> items, bool onlyCompleted)
    {
        var genreItems = new Dictionary<string, List<MediaItem>>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in items)
        {
            var isEligible = onlyCompleted
                ? item.Status == MediaStatus.Completed
                : item.Status != MediaStatus.Planned;

            if (!isEligible || string.IsNullOrWhiteSpace(item.Genres))
            {
                continue;
            }

            foreach (var rawGenre in GenreNormalizer.ExtractGenres(item.Genres))
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
        double mangaChapterMinutes,
        bool onlyCompleted)
    {
        var lowScoreItems = items
            .Where(item => onlyCompleted
                ? item.Status == MediaStatus.Completed && item.Score.HasValue && item.Score.Value <= 5
                : ((item.Score.HasValue && item.Score.Value <= 5 && item.Status != MediaStatus.Planned) || item.Status == MediaStatus.Dropped))
            .ToList();

        var breakdown = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        double lowScoreHours = 0;
        foreach (var item in lowScoreItems)
        {
            var hours = CalculateItemHours(item, bookPageMinutes, mangaChapterMinutes, onlyCompleted);
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
    private static double CalculateItemHours(MediaItem item, double bookPageMinutes, double mangaChapterMinutes, bool onlyCompleted) => item switch
    {
        VideoGame game => (onlyCompleted ? game.Status == MediaStatus.Completed : game.Status != MediaStatus.Planned) ? game.HoursPlayed ?? 0 : 0,
        Movie movie => (onlyCompleted ? movie.Status == MediaStatus.Completed : movie.Status != MediaStatus.Planned)
            ? (movie.DurationMinutes > 0 ? movie.DurationMinutes : (movie.Status == MediaStatus.Completed ? 90 : 0)) / 60.0
            : 0,
        TvShow show => CalculateShowHours(show, onlyCompleted),
        Book book => (onlyCompleted ? book.Status == MediaStatus.Completed : book.Status != MediaStatus.Planned)
            ? CalculateBookPages(book) * bookPageMinutes / 60.0
            : 0,
        Manga manga => CalculateMangaChapters(manga, mangaChapterMinutes, onlyCompleted),
        _ => 0,
    };

    private static double CalculateShowHours(TvShow show, bool onlyCompleted)
    {
        if (onlyCompleted && show.Status != MediaStatus.Completed)
        {
            return 0;
        }

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

    private static double CalculateMangaChapters(Manga manga, double mangaChapterMinutes, bool onlyCompleted)
    {
        if (onlyCompleted ? manga.Status != MediaStatus.Completed : manga.Status == MediaStatus.Planned)
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
    private static CriticalDivergenceDto CalculateDivergence(IReadOnlyCollection<MediaItem> items, bool onlyCompleted)
    {
        var scored = items
            .Where(item => item.Score is >= 1 && item.ExternalRating is > 0 &&
                           (onlyCompleted ? item.Status == MediaStatus.Completed : item.Status != MediaStatus.Planned))
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
    private static List<GenreCompletionStatDto> BuildGenreParadox(Dictionary<string, List<MediaItem>> genreItems)
    {
        var raw = genreItems
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
            .Where(x => x.TrackedCount >= 1)
            .OrderByDescending(x => x.TrackedCount)
            .ThenBy(x => x.Genre, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var filtered = raw.Where(x => x.TrackedCount >= 2).ToList();
        var candidates = filtered.Count >= 2 ? filtered : raw;

        return candidates
            .Take(6)
            .Select(x => new GenreCompletionStatDto(
                x.Genre,
                x.TrackedCount,
                x.Completed,
                x.Dropped,
                Math.Round((double)x.Completed / x.TrackedCount * 100.0, 1, MidpointRounding.AwayFromZero),
                Math.Round((double)x.Dropped / x.TrackedCount * 100.0, 1, MidpointRounding.AwayFromZero)))
            .ToList();
    }

    /// <summary>"Golden era": decades of the user's favorite titles (rated 8+ or completed).</summary>
    private static List<EraAffinityStatDto> BuildEraAffinity(IReadOnlyCollection<MediaItem> items, bool onlyCompleted)
    {
        var favorites = items.Where(item => onlyCompleted
            ? item.Status == MediaStatus.Completed
            : (item.Status == MediaStatus.Completed || (item.Status != MediaStatus.Planned && item.Score >= 8)));

        var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var total = 0;
        foreach (var item in favorites)
        {
            var era = GetEra(ExtractYear(item));
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

    private static int? ExtractYear(MediaItem item)
    {
        if (item.ReleaseYear is > 0)
        {
            return item.ReleaseYear.Value;
        }

        if (item.ReleaseDate.HasValue)
        {
            return item.ReleaseDate.Value.Year;
        }

        if (item.FinishedAt.HasValue)
        {
            return item.FinishedAt.Value.Year;
        }

        if (item.CreatedAt != default)
        {
            return item.CreatedAt.Year;
        }

        return null;
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
        Dictionary<string, List<MediaItem>> genreItems,
        bool onlyCompleted)
    {
        var activeItems = items
            .Where(item => onlyCompleted ? item.Status == MediaStatus.Completed : item.Status != MediaStatus.Planned)
            .ToList();

        var activeTypes = activeItems
            .Select(AdvancedStatsCalculator.GetMediaTypeName)
            .Where(type => type != "other")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();

        var scoredCount = advancedStats.ScoreDistribution?.Values.Sum() ?? 0;
        var totalHours = advancedStats.TotalHours;

        // 1. Rating Extremes (Score psychology)
        if (scoredCount >= 10 && advancedStats.AverageScore <= 6.5)
        {
            return new TastePersonaDto(
                "Strict Critic",
                "You hold your library to sky-high standards: few titles manage to impress you, and even the world's favorites earn a skeptical squint.",
                "critic",
                ["high_standards", "honest_reviews", "uncompromising_taste"]);
        }

        if (scoredCount >= 10 && advancedStats.AverageScore >= 8.5)
        {
            return new TastePersonaDto(
                "Generous Enthusiast",
                "You fall in love with stories whole-heartedly and hand out top scores with infectious joy. Media is a source of pure delight.",
                "enthusiast",
                ["pure_enthusiasm", "generous_marks", "open_heart"]);
        }

        // 2. Discipline Extremes (Completion discipline)
        if (advancedStats.TotalTitles >= 20 && advancedStats.CompletionRatePercent >= 80.0)
        {
            return new TastePersonaDto(
                "Perfectionist Completer",
                "You never leave a story half-read: if you start something, you finish it. Dropping a title is a defeat you almost never allow yourself.",
                "perfectionist",
                ["finisher", "no_dnf", "iron_focus"]);
        }

        if (advancedStats.TotalTitles >= 50 && advancedStats.CompletionRatePercent <= 25.0)
        {
            return new TastePersonaDto(
                "Tsundoku Master",
                "The thrill of discovery outpaces the clock: your backlog is a grand treasury of endless possibilities waiting to be explored.",
                "tsundoku_master",
                ["infinite_backlog", "treasure_hunter", "dreamer"]);
        }

        // Media type counts
        var mangaCount = activeItems.Count(x => x is Manga);
        var animeCount = activeItems.Count(x => (x is Movie m && m.IsAnime) || (x is TvShow s && s.IsAnime));
        var gameCount = activeItems.Count(x => x is VideoGame);
        var bookCount = activeItems.Count(x => x is Book);
        var movieCount = activeItems.Count(x => x is Movie m && !m.IsAnime);
        var seriesCount = activeItems.Count(x => x is TvShow s && !s.IsAnime);

        // 3. Format Dominance (Specific media types)
        var isMangaDominant = (totalHours > 0 && advancedStats.MangaHours > totalHours * 0.4)
            || advancedStats.TotalChaptersRead >= 100
            || (mangaCount >= 15 && mangaCount >= animeCount * 2);

        if (isMangaDominant)
        {
            return new TastePersonaDto(
                "Manga Digger",
                "Ink, panels, and dynamic pacing define your media life. You devour hundreds of chapters in a single sitting and live for weekly cliffhangers.",
                "manga_reader",
                ["chapter_hunter", "manhwa_connoisseur", "visual_pacing"]);
        }

        if (totalHours > 0 && advancedStats.AnimeHours > totalHours * 0.4 && animeCount >= 15)
        {
            return new TastePersonaDto(
                "Anime Cinephile",
                "Anime claims the crown in your free time: you track visionary directors, celebrate sakuga animation, and recognize favorite voice actors instantly.",
                "otaku",
                ["anime_focus", "studio_connoisseur", "sakuga_lover"]);
        }

        if (totalHours > 0 && advancedStats.GameHours > totalHours * 0.4 && advancedStats.GameHours >= 50.0)
        {
            return new TastePersonaDto(
                "Hardcore Gamer",
                "Interactive experiences trump passive watching every time. You dive into complex mechanics and spend dozens of hours exploring virtual worlds.",
                "gamer",
                ["deep_immersion", "mechanics_master", "interactive_focus"]);
        }

        if (totalHours > 0 && (advancedStats.BookHours > totalHours * 0.4 || (advancedStats.TotalPagesRead >= 1000 && bookCount >= 5)))
        {
            return new TastePersonaDto(
                "Literary Bookworm",
                "You revere the written word, deep character monologues, and narrative depth. Amidst rapid-fire media, you stay true to great literature.",
                "bookworm",
                ["power_of_prose", "mindful_reading", "rich_imagination"]);
        }

        if (totalHours > 0 && advancedStats.MovieHours > totalHours * 0.4 && movieCount >= 15)
        {
            return new TastePersonaDto(
                "Cinephile Connoisseur",
                "Cinema is the purest stage for your dramatic sensibilities. You appreciate framing, lighting, and directorial vision in focused feature films.",
                "cinephile",
                ["visual_language", "auteur_cinema", "directorial_style"]);
        }

        if (totalHours > 0 && (advancedStats.SeriesHours > totalHours * 0.4 || advancedStats.SeriesEpisodesWatched >= 50) && seriesCount >= 5)
        {
            return new TastePersonaDto(
                "Serial Binger",
                "You love sprawling narrative arcs that unfold across multiple seasons. The 'Next Episode' prompt is an irresistible reflex.",
                "serial_binger",
                ["season_binger", "complex_plotlines", "serial_enthusiast"]);
        }

        // 4. Genre Atmosphere Dominance
        var totalGenreOccurrences = genreItems.Values.Sum(v => v.Count);
        if (totalGenreOccurrences >= 5)
        {
            var darkCount = genreItems
                .Where(kv => kv.Key is "Psychological" or "Seinen" or "Mystery" or "Dark Fantasy" or "Philosophical")
                .Sum(kv => kv.Value.Count);
            if ((double)darkCount / totalGenreOccurrences >= 0.25)
            {
                return new TastePersonaDto(
                    "Seinen Philosopher",
                    "You gravitate toward psychological tension, morally grey antiheroes, and dark suspense, exploring the shadows of the human condition.",
                    "dark_philosopher",
                    ["grim_realism", "psychological_depth", "philosophical_nuance"]);
            }

            var cozyCount = genreItems
                .Where(kv => kv.Key is "Slice of Life" or "Comedy" or "Romance")
                .Sum(kv => kv.Value.Count);
            if ((double)cozyCount / totalGenreOccurrences >= 0.30)
            {
                return new TastePersonaDto(
                    "Cozy Hedonist",
                    "Slice of life, warm humor, and gentle romance are your sanctuary. You cherish comforting atmospheres and heartwarming tales.",
                    "cozy_hedonist",
                    ["cozy_vibes", "warmhearted_tales", "stress_free_comfort"]);
            }

            var actionCount = genreItems
                .Where(kv => kv.Key is "Action" or "Shounen" or "Thriller")
                .Sum(kv => kv.Value.Count);
            if ((double)actionCount / totalGenreOccurrences >= 0.30)
            {
                return new TastePersonaDto(
                    "Action Junkie",
                    "You live for breathtaking spectacles, pulsing adrenaline, and climactic showdowns where stakes and tempo are pushed to the limit.",
                    "action_junkie",
                    ["high_tempo", "kinetic_spectacle", "fighting_spirit"]);
            }

            var sciFiCount = genreItems
                .Where(kv => kv.Key is "Sci-Fi" or "Cyberpunk")
                .Sum(kv => kv.Value.Count);
            if ((double)sciFiCount / totalGenreOccurrences >= 0.25)
            {
                return new TastePersonaDto(
                    "Futurist Visionary",
                    "Science fiction and cyberpunk lead your collection: you gravitate to worlds where future technology and human nature collide.",
                    "visionary",
                    ["future_genres", "tech_and_space", "expansive_horizons"]);
            }
        }

        // 5. Broad Media Omnivore
        if (activeTypes >= 3 && advancedStats.TotalTitles >= 15)
        {
            return new TastePersonaDto(
                "Cultural Omnivore",
                "You taste everything the culture industry serves: games, cinema, series, books, and manga share your time in harmonic balance.",
                "omnivore",
                ["all_formats", "no_genre_limits", "eclectic_appetite"]);
        }

        // 6. Base / Default
        return new TastePersonaDto(
            "Thoughtful Archivist",
            "You move at your own pace: slower, deeper, without chasing trends. Your library grows drop by drop, chosen mindfully.",
            "archivist",
            ["mindful_pace", "depth_over_speed", "intentional_curation"]);
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
