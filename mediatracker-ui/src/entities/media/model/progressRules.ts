import {
  type BookMedia,
  type GameMedia,
  type MangaMedia,
  type MediaItem,
  type TvShowMedia,
} from "$shared/types";

export function clampProgress(current: number, total: number | null | undefined): number {
  const safeCurrent = Math.max(current, 0);
  return total !== null && total !== undefined && total > 0
    ? Math.min(safeCurrent, total)
    : safeCurrent;
}

/** Games, books, manga and shows expose the user-driven field each of these reads. */
export function readCardProgress(item: MediaItem): number {
  switch (item.type) {
    case "game":
      return (item as GameMedia).hoursPlayed ?? 0;
    case "book": {
      const book = item as BookMedia;
      return book.format === "light_novel" || book.format === "web_novel"
        ? (book.currentChapter ?? 0)
        : book.currentPage;
    }
    case "manga":
      return (item as MangaMedia).currentChapter;
    case "tvshow":
      return (item as TvShowMedia).totalEpisodesWatched ?? 0;
    default:
      return 0;
  }
}

export function cardProgressTotal(item: MediaItem): number | null {
  switch (item.type) {
    case "book": {
      const book = item as BookMedia;
      return book.format === "light_novel" || book.format === "web_novel"
        ? (book.totalChapters ?? null)
        : book.totalPages;
    }
    case "manga":
      return (item as MangaMedia).totalChapters;
    default:
      return null;
  }
}

/**
 * Mirrors {@link readCardProgress} for writes: keeps the raw item object in
 * sync with an optimistic step, so a parent map that spreads the item (e.g. a
 * status flip) carries the new progress instead of reverting it.
 */
export function writeCardProgress(item: MediaItem, value: number): void {
  switch (item.type) {
    case "game":
      (item as GameMedia).hoursPlayed = value;
      break;
    case "book": {
      const book = item as BookMedia;
      if (book.format === "light_novel" || book.format === "web_novel") {
        book.currentChapter = value;
      } else {
        book.currentPage = value;
      }
      break;
    }
    case "manga":
      (item as MangaMedia).currentChapter = value;
      break;
    case "tvshow":
      (item as TvShowMedia).totalEpisodesWatched = value;
      break;
  }
}

/** Only games, books and manga carry a stepper; movies and shows do not. */
export function supportsProgressStepper(item: MediaItem): boolean {
  return (
    item.type === "game" || item.type === "book" || item.type === "manga" || item.type === "tvshow"
  );
}

/** Next value after a +/- press, clamped to the known total (never below zero). */
export function nextCardProgress(item: MediaItem, current: number, delta: number): number {
  return clampProgress(current + delta, cardProgressTotal(item));
}

/**
 * Rule 1 of the status contract: the exact 0 → 1 step implies the title is being consumed
 * right now and promotes it to InProgress. Any other progress change keeps the current status —
 * dropped stays dropped, on hold stays on hold, planned stays planned. Mirrors the backend's
 * ProgressStepperRules.PromotesToInProgress, so an optimistic click never diverges from the
 * server's stored state.
 */
export function shouldPromoteToInProgress(previous: number, next: number): boolean {
  return previous === 0 && next === 1;
}
