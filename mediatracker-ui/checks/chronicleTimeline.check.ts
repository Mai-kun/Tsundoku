// Self-check for chronicleTimeline: grouping, sorting, averageScore, topRatedItem, filtering, undated.
// Run: node --experimental-strip-types checks/chronicleTimeline.check.ts
import assert from "node:assert/strict";
import { buildChronicle } from "../src/entities/media/model/chronicleTimeline.ts";
import type { MediaItem, GameMedia, MovieMedia, TvShowMedia } from "../src/shared/types/models.ts";
import { MEDIA_STATUS } from "../src/shared/types/enums.ts";

// ─── Helpers ────────────────────────────────────────────────────────────────

function game(id: string, overrides: Partial<GameMedia> = {}): GameMedia {
    return {
        id,
        type: "game",
        title: `Game ${id}`,
        status: MEDIA_STATUS.completed,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2024-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        platform: "PC",
        hoursPlayed: null,
        ...overrides,
    };
}

function movie(id: string, overrides: Partial<MovieMedia> = {}): MovieMedia {
    return {
        id,
        type: "movie",
        title: `Movie ${id}`,
        status: MEDIA_STATUS.completed,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2024-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        durationMinutes: 120,
        director: null,
        isAnime: false,
        studio: null,
        romajiTitle: null,
        ...overrides,
    };
}

function tvshow(id: string, overrides: Partial<TvShowMedia> = {}): TvShowMedia {
    return {
        id,
        type: "tvshow",
        title: `TvShow ${id}`,
        status: MEDIA_STATUS.completed,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2024-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        isAnime: false,
        studio: null,
        romajiTitle: null,
        network: null,
        totalEpisodesCount: 12,
        totalEpisodesWatched: 12,
        seasonsCount: 1,
        ...overrides,
    };
}

// ─── Test 1: Grouping by year/month, descending order ────────────────────────
{
    const items: MediaItem[] = [
        game("g1", { finishedAt: "2024-03-10T00:00:00Z", score: 8 }),
        game("g2", { finishedAt: "2024-11-01T00:00:00Z", score: 9 }),
        game("g3", { finishedAt: "2025-01-15T00:00:00Z", score: 7 }),
        game("g4", { finishedAt: "2024-03-20T00:00:00Z", score: null }),
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });

    // Years descending
    assert.deepEqual(
        result.years.map((y) => y.year),
        [2025, 2024],
        "Years should be in descending order",
    );

    const year2024 = result.years.find((y) => y.year === 2024)!;
    // Months descending: November (10) before March (2)
    assert.deepEqual(
        year2024.months.map((m) => m.month),
        [10, 2],
        "Months should be in descending order (10=Nov, 2=Mar)",
    );

    // Entries within March sorted newest → oldest
    const marchGroup = year2024.months.find((m) => m.month === 2)!;
    assert.equal(marchGroup.entries[0].item.id, "g4", "Newer entry (Mar 20) should come first");
    assert.equal(marchGroup.entries[1].item.id, "g1", "Older entry (Mar 10) should come second");

    console.log("ok   Test 1: year/month grouping and descending order");
}

// ─── Test 2: averageScore and topRatedItem ────────────────────────────────────
{
    const items: MediaItem[] = [
        game("g1", { finishedAt: "2024-06-01T00:00:00Z", score: 8 }),
        game("g2", { finishedAt: "2024-06-15T00:00:00Z", score: 6 }),
        game("g3", { finishedAt: "2024-06-20T00:00:00Z", score: 10 }),
        game("g4", { finishedAt: "2024-06-25T00:00:00Z", score: null }), // no score
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });
    const year = result.years[0]!;

    // avg of 8, 6, 10 = 24/3 = 8.0
    assert.equal(year.averageScore, 8, "Year averageScore should be 8.0");

    // topRatedItem should be g3 (score 10)
    assert.equal(year.topRatedItem?.id, "g3", "topRatedItem should be the one with score 10");

    // Month average: same items in one month
    const juneGroup = year.months[0]!;
    assert.equal(juneGroup.averageScore, 8, "Month averageScore should be 8.0");

    console.log("ok   Test 2: averageScore and topRatedItem");
}

// ─── Test 3: Category filtering ───────────────────────────────────────────────
{
    const items: MediaItem[] = [
        game("g1", { finishedAt: "2024-05-01T00:00:00Z" }),
        movie("m1", { finishedAt: "2024-05-02T00:00:00Z", isAnime: false }),
        movie("m2", { finishedAt: "2024-05-03T00:00:00Z", isAnime: true }), // anime movie
        tvshow("tv1", { finishedAt: "2024-05-04T00:00:00Z", isAnime: true }), // anime tvshow
        tvshow("tv2", { finishedAt: "2024-05-05T00:00:00Z", isAnime: false }), // regular tvshow
    ];

    // Filter: anime → should include m2 and tv1 only
    const animeResult = buildChronicle(items, { category: "anime", includeInProgress: false });
    const animeIds = animeResult.years[0]?.entries.map((e) => e.item.id).sort();
    assert.deepEqual(animeIds, ["m2", "tv1"], "anime filter should include anime movies and anime tvshows");

    // Filter: movie → should include m1 only (non-anime movies)
    const movieResult = buildChronicle(items, { category: "movie", includeInProgress: false });
    const movieIds = movieResult.years[0]?.entries.map((e) => e.item.id).sort();
    assert.deepEqual(movieIds, ["m1"], "movie filter should include only non-anime movies");

    // Filter: tvshow → should include tv2 only (non-anime tvshows)
    const tvResult = buildChronicle(items, { category: "tvshow", includeInProgress: false });
    const tvIds = tvResult.years[0]?.entries.map((e) => e.item.id).sort();
    assert.deepEqual(tvIds, ["tv2"], "tvshow filter should include only non-anime tvshows");

    // Filter: game → only g1
    const gameResult = buildChronicle(items, { category: "game", includeInProgress: false });
    const gameIds = gameResult.years[0]?.entries.map((e) => e.item.id).sort();
    assert.deepEqual(gameIds, ["g1"], "game filter should include only games");

    // Filter: all → all 5
    const allResult = buildChronicle(items, { category: "all", includeInProgress: false });
    assert.equal(allResult.totalDatedCount, 5, "all filter should include all 5 items");

    console.log("ok   Test 3: category filtering (anime vs tvshow vs movie vs game)");
}

// ─── Test 4: Undated completed → undatedCompleted ────────────────────────────
{
    const items: MediaItem[] = [
        game("g_dated", { finishedAt: "2024-09-01T00:00:00Z" }),
        game("g_undated1", { finishedAt: null, startedAt: null }), // no dates → undated
        game("g_undated2", { finishedAt: null, startedAt: null }), // no dates → undated
        game("g_startedonly", { finishedAt: null, startedAt: "2024-08-01T00:00:00Z" }), // startedAt used as fallback
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });

    assert.equal(result.undatedCompleted.length, 2, "Two items with no dates should be in undatedCompleted");
    assert.ok(
        result.undatedCompleted.some((i) => i.id === "g_undated1"),
        "g_undated1 should be in undatedCompleted",
    );
    assert.ok(
        result.undatedCompleted.some((i) => i.id === "g_undated2"),
        "g_undated2 should be in undatedCompleted",
    );
    // g_startedonly should use startedAt as date and appear in timeline
    assert.equal(result.totalDatedCount, 2, "g_dated and g_startedonly should be in the timeline");

    console.log("ok   Test 4: completed without dates go to undatedCompleted");
}

// ─── Test 5: includeInProgress ────────────────────────────────────────────────
{
    const items: MediaItem[] = [
        game("g_done", { finishedAt: "2024-04-01T00:00:00Z", status: MEDIA_STATUS.completed }),
        game("g_ip_dated", {
            status: MEDIA_STATUS.inProgress,
            startedAt: "2024-04-15T00:00:00Z",
            finishedAt: null,
        }),
        game("g_ip_nodates", {
            status: MEDIA_STATUS.inProgress,
            startedAt: null,
            finishedAt: null,
        }),
    ];

    const withoutIP = buildChronicle(items, { category: "all", includeInProgress: false });
    assert.equal(withoutIP.totalDatedCount, 1, "Without includeInProgress: only completed item");

    const withIP = buildChronicle(items, { category: "all", includeInProgress: true });
    assert.equal(withIP.totalDatedCount, 2, "With includeInProgress: completed + in-progress with startedAt");
    const ipEntry = withIP.years[0]?.entries.find((e) => e.item.id === "g_ip_dated");
    assert.equal(ipEntry?.isCompleted, false, "In-progress entry should have isCompleted=false");

    console.log("ok   Test 5: includeInProgress adds in-progress items with startedAt");
}

console.log("\nAll chronicleTimeline checks passed ✓");
