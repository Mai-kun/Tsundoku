import { describe, it, expect } from "vitest";
import { evaluateTimeFit, formatTimeBudgetChip } from "../timeBudget";
import type {
  BookMedia,
  GameMedia,
  MangaMedia,
  MovieMedia,
  TvShowMedia,
} from "$shared/types/models";

function createMovie(durationMinutes: number): MovieMedia {
  return {
    id: "movie-1",
    type: "movie",
    title: "Test Movie",
    status: 1,
    score: null,
    startedAt: null,
    finishedAt: null,
    coverUrl: null,
    createdAt: "2026-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    durationMinutes,
    director: null,
    isAnime: false,
    studio: null,
    romajiTitle: null,
  };
}

function createTvShow(opts: {
  durationMinutes?: number;
  isAnime?: boolean;
  totalEpisodesCount: number;
  totalEpisodesWatched: number;
}): TvShowMedia {
  return {
    id: "tv-1",
    type: "tvshow",
    title: "Test TV Show",
    status: 1,
    score: null,
    startedAt: null,
    finishedAt: null,
    coverUrl: null,
    createdAt: "2026-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    isAnime: opts.isAnime ?? false,
    studio: null,
    romajiTitle: null,
    network: null,
    seasonsCount: 1,
    totalEpisodesCount: opts.totalEpisodesCount,
    totalEpisodesWatched: opts.totalEpisodesWatched,
    durationMinutes: opts.durationMinutes,
  };
}

function createBook(currentPage: number, totalPages: number): BookMedia {
  return {
    id: "book-1",
    type: "book",
    title: "Test Book",
    status: 1,
    score: null,
    startedAt: null,
    finishedAt: null,
    coverUrl: null,
    createdAt: "2026-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    author: "Author",
    currentPage,
    totalPages,
  };
}

function createManga(currentChapter: number, totalChapters: number | null): MangaMedia {
  return {
    id: "manga-1",
    type: "manga",
    title: "Test Manga",
    status: 1,
    score: null,
    startedAt: null,
    finishedAt: null,
    coverUrl: null,
    createdAt: "2026-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    currentChapter,
    totalChapters,
    currentVolume: 1,
  };
}

function createGame(): GameMedia {
  return {
    id: "game-1",
    type: "game",
    title: "Test Game",
    status: 1,
    score: null,
    startedAt: null,
    finishedAt: null,
    coverUrl: null,
    createdAt: "2026-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    platform: "PC",
    hoursPlayed: 5,
  };
}

describe("timeBudget", () => {
  it("rejects long movie and episode in 15 min slot, accepts book and manga", () => {
    const movie120 = createMovie(120);
    const movieRes = evaluateTimeFit(movie120, 15, 1.5, 6.0, "ru");
    expect(movieRes.fits).toBe(false);

    const tv45 = createTvShow({
      durationMinutes: 45,
      isAnime: false,
      totalEpisodesCount: 10,
      totalEpisodesWatched: 0,
    });
    const tvRes = evaluateTimeFit(tv45, 15, 1.5, 6.0, "ru");
    expect(tvRes.fits).toBe(false);

    const book = createBook(50, 300);
    const bookRes = evaluateTimeFit(book, 15, 1.5, 6.0, "ru");
    expect(bookRes.fits).toBe(true);
    expect(bookRes.sessionLabel).toBe("За сессию: ~10 стр.");

    const manga = createManga(10, 50);
    const mangaRes = evaluateTimeFit(manga, 15, 1.5, 6.0, "ru");
    expect(mangaRes.fits).toBe(true);
    expect(mangaRes.sessionLabel).toBe("Успеете: ~2 гл.");
  });

  it("evaluates anime episodes in 30 min slot and marks final episode finish", () => {
    const animeOngoing = createTvShow({
      durationMinutes: 24,
      isAnime: true,
      totalEpisodesCount: 12,
      totalEpisodesWatched: 5,
    });
    const ongoingRes = evaluateTimeFit(animeOngoing, 30, 1.5, 6.0, "ru");
    expect(ongoingRes.fits).toBe(true);
    expect(ongoingRes.canFinishNow).toBe(false);
    expect(ongoingRes.sessionLabel).toBe("Успеете: 1 эп. (~24 мин.)");

    const animeFinal = createTvShow({
      durationMinutes: 24,
      isAnime: true,
      totalEpisodesCount: 12,
      totalEpisodesWatched: 11,
    });
    const finalRes = evaluateTimeFit(animeFinal, 30, 1.5, 6.0, "ru");
    expect(finalRes.fits).toBe(true);
    expect(finalRes.canFinishNow).toBe(true);
    expect(finalRes.sessionLabel).toBe("🔥 Добить финал: 1 эп. (~24 мин.)");
  });

  it("fits 110 min movie into 120 min slot and marks canFinishNow", () => {
    const movie110 = createMovie(110);
    const movieRes = evaluateTimeFit(movie110, 120, 1.5, 6.0, "ru");
    expect(movieRes.fits).toBe(true);
    expect(movieRes.canFinishNow).toBe(true);
    expect(movieRes.sessionLabel).toBe("🔥 Целиком: 110 мин.");
  });

  it("evaluates edge cases for games, book finishing, and English locale", () => {
    const game = createGame();
    expect(evaluateTimeFit(game, 15, 1.5, 6.0, "ru").fits).toBe(false);
    expect(evaluateTimeFit(game, 30, 1.5, 6.0, "ru").fits).toBe(true);
    expect(evaluateTimeFit(game, 30, 1.5, 6.0, "ru").sessionLabel).toBe("Игровая сессия: 30 мин.");

    const almostDoneBook = createBook(195, 200);
    const bookFinish = evaluateTimeFit(almostDoneBook, 15, 1.5, 6.0, "ru");
    expect(bookFinish.canFinishNow).toBe(true);
    expect(bookFinish.sessionLabel).toBe("🔥 Дочитать до конца: 5 стр. (~8 мин.)");

    const movieEn = evaluateTimeFit(createMovie(90), 90, 1.5, 6.0, "en");
    expect(movieEn.sessionLabel).toBe("🔥 Entire: 90 min");
  });

  it("formats time budget chips properly for various durations and locales", () => {
    expect(formatTimeBudgetChip(15, "ru")).toBe("15 м");
    expect(formatTimeBudgetChip(15, "en")).toBe("15m");
    expect(formatTimeBudgetChip(40, "ru")).toBe("40 м");
    expect(formatTimeBudgetChip(40, "en")).toBe("40m");
    expect(formatTimeBudgetChip(60, "ru")).toBe("1 ч");
    expect(formatTimeBudgetChip(60, "en")).toBe("1h");
    expect(formatTimeBudgetChip(90, "ru")).toBe("1.5 ч");
    expect(formatTimeBudgetChip(90, "en")).toBe("1.5h");
    expect(formatTimeBudgetChip(120, "ru")).toBe("2 ч");
    expect(formatTimeBudgetChip(120, "en")).toBe("2h");
    expect(formatTimeBudgetChip(150, "ru")).toBe("2.5 ч");
    expect(formatTimeBudgetChip(150, "en")).toBe("2.5h");
    expect(formatTimeBudgetChip(75, "ru")).toBe("1ч 15м");
    expect(formatTimeBudgetChip(75, "en")).toBe("1h 15m");
  });
});
