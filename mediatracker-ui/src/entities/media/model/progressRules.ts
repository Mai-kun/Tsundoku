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

/** Games, books and manga expose the user-driven field each of these reads. */
export function readCardProgress(item: MediaItem): number {
  switch (item.type) {
    case "game":
      return (item as GameMedia).hoursPlayed ?? 0;
    case "book":
      return (item as BookMedia).currentPage;
    case "manga":
      return (item as MangaMedia).currentChapter;
    default:
      return 0;
  }
}

export function cardProgressTotal(item: MediaItem): number | null {
  switch (item.type) {
    case "book":
      return (item as BookMedia).totalPages;
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
    case "book":
      (item as BookMedia).currentPage = value;
      break;
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
    item.type === "game" ||
    item.type === "book" ||
    item.type === "manga" ||
    item.type === "tvshow"
  );
}

/** Next value after a +/- press, clamped to the known total (never below zero). */
export function nextCardProgress(item: MediaItem, current: number, delta: number): number {
  return clampProgress(current + delta, cardProgressTotal(item));
}
