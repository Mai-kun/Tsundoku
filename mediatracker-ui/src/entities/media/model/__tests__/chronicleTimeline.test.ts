import { describe, it, expect } from "vitest";
import { buildChronicle } from "../chronicleTimeline";
import type { MediaItem, GameMedia, MovieMedia, TvShowMedia } from "$shared/types/models";
import { MEDIA_STATUS } from "$shared/types/enums";

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

describe("chronicleTimeline", () => {
  it("groups items by year and month in descending order", () => {
    const items: MediaItem[] = [
      game("g1", { finishedAt: "2024-03-10T00:00:00Z", score: 8 }),
      game("g2", { finishedAt: "2024-11-01T00:00:00Z", score: 9 }),
      game("g3", { finishedAt: "2025-01-15T00:00:00Z", score: 7 }),
      game("g4", { finishedAt: "2024-03-20T00:00:00Z", score: null }),
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });

    expect(result.years.map((y) => y.year)).toEqual([2025, 2024]);

    const year2024 = result.years.find((y) => y.year === 2024)!;
    expect(year2024.months.map((m) => m.month)).toEqual([10, 2]);

    const marchGroup = year2024.months.find((m) => m.month === 2)!;
    expect(marchGroup.entries[0].item.id).toBe("g4");
    expect(marchGroup.entries[1].item.id).toBe("g1");
  });

  it("calculates averageScore and topRatedItem correctly", () => {
    const items: MediaItem[] = [
      game("g1", { finishedAt: "2024-06-01T00:00:00Z", score: 8 }),
      game("g2", { finishedAt: "2024-06-15T00:00:00Z", score: 6 }),
      game("g3", { finishedAt: "2024-06-20T00:00:00Z", score: 10 }),
      game("g4", { finishedAt: "2024-06-25T00:00:00Z", score: null }),
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });
    const year = result.years[0]!;

    expect(year.averageScore).toBe(8);
    expect(year.topRatedItem?.id).toBe("g3");

    const juneGroup = year.months[0]!;
    expect(juneGroup.averageScore).toBe(8);
  });

  it("filters properly by category (anime, movie, tvshow, game, all)", () => {
    const items: MediaItem[] = [
      game("g1", { finishedAt: "2024-05-01T00:00:00Z" }),
      movie("m1", { finishedAt: "2024-05-02T00:00:00Z", isAnime: false }),
      movie("m2", { finishedAt: "2024-05-03T00:00:00Z", isAnime: true }),
      tvshow("tv1", { finishedAt: "2024-05-04T00:00:00Z", isAnime: true }),
      tvshow("tv2", { finishedAt: "2024-05-05T00:00:00Z", isAnime: false }),
    ];

    const animeResult = buildChronicle(items, { category: "anime", includeInProgress: false });
    const animeIds = animeResult.years[0]?.entries.map((e) => e.item.id).sort();
    expect(animeIds).toEqual(["m2", "tv1"]);

    const movieResult = buildChronicle(items, { category: "movie", includeInProgress: false });
    const movieIds = movieResult.years[0]?.entries.map((e) => e.item.id).sort();
    expect(movieIds).toEqual(["m1"]);

    const tvResult = buildChronicle(items, { category: "tvshow", includeInProgress: false });
    const tvIds = tvResult.years[0]?.entries.map((e) => e.item.id).sort();
    expect(tvIds).toEqual(["tv2"]);

    const gameResult = buildChronicle(items, { category: "game", includeInProgress: false });
    const gameIds = gameResult.years[0]?.entries.map((e) => e.item.id).sort();
    expect(gameIds).toEqual(["g1"]);

    const allResult = buildChronicle(items, { category: "all", includeInProgress: false });
    expect(allResult.totalDatedCount).toBe(5);
  });

  it("places undated completed items into undatedCompleted", () => {
    const items: MediaItem[] = [
      game("g_dated", { finishedAt: "2024-09-01T00:00:00Z" }),
      game("g_undated1", { finishedAt: null, startedAt: null }),
      game("g_undated2", { finishedAt: null, startedAt: null }),
      game("g_startedonly", { finishedAt: null, startedAt: "2024-08-01T00:00:00Z" }),
    ];

    const result = buildChronicle(items, { category: "all", includeInProgress: false });

    expect(result.undatedCompleted.length).toBe(2);
    expect(result.undatedCompleted.some((i) => i.id === "g_undated1")).toBe(true);
    expect(result.undatedCompleted.some((i) => i.id === "g_undated2")).toBe(true);
    expect(result.totalDatedCount).toBe(2);
  });

  it("respects includeInProgress flag", () => {
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
    expect(withoutIP.totalDatedCount).toBe(1);

    const withIP = buildChronicle(items, { category: "all", includeInProgress: true });
    expect(withIP.totalDatedCount).toBe(2);
    const ipEntry = withIP.years[0]?.entries.find((e) => e.item.id === "g_ip_dated");
    expect(ipEntry?.isCompleted).toBe(false);
  });
});
