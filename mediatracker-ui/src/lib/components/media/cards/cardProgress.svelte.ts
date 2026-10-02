import { untrack } from "svelte";
import {
    clampProgress,
    MEDIA_STATUS,
    type BookMedia,
    type GameMedia,
    type MangaMedia,
    type MediaItem,
} from "$lib/types";
import { createProgressDebounce } from "$lib/utils/progressDebounce";

export interface CardProgressState {
    readonly value: number;
    readonly error: unknown;
    step(delta: number): void;
}

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

/** Games, books and manga carry a user-driven progress field; movies/shows do not. */
export function supportsProgressStepper(item: MediaItem): boolean {
    if (item.status !== MEDIA_STATUS.inProgress) return false;
    return (
        item.type === "game" || item.type === "book" || item.type === "manga"
    );
}

/** Next value after a +/- press, clamped to the known total (never below zero). */
export function nextCardProgress(
    item: MediaItem,
    current: number,
    delta: number,
): number {
    return clampProgress(current + delta, cardProgressTotal(item));
}

export interface CardProgressOptions {
    /** Accessor, not a value: the item prop is replaced when the grid refetches. */
    getItem: () => MediaItem;
    getOnProgress: () =>
        | ((id: string, currentProgress: number) => Promise<void>)
        | undefined;
    getOnProgressCommitted: () => () => void;
}

export function createCardProgress(
    options: CardProgressOptions,
): CardProgressState {
    let trackedItem: MediaItem | null = null;
    let currentProgress = $state(
        untrack(() => readCardProgress(options.getItem())),
    );
    let committedProgress = $state(untrack(() => currentProgress));
    let pendingSnapshot = $state<number | null>(null);
    let error = $state<unknown>(null);

    const debounce = createProgressDebounce({
        send: (id, value) =>
            (options.getOnProgress() ?? (async () => {}))(id, value),
        buildRequest: (id, value) => ({
            url: `/api/media/${id}/progress`,
            body: { currentProgress: value },
        }),
        onCommitted: (value) => {
            committedProgress = value;
            if (currentProgress === value) options.getOnProgressCommitted()();
        },
        onError: (failure) => {
            currentProgress = pendingSnapshot ?? committedProgress;
            committedProgress = currentProgress;
            pendingSnapshot = null;
            error = failure;
        },
    });

    $effect(() => {
        const item = options.getItem();
        if (item !== trackedItem) {
            trackedItem = item;
            currentProgress = readCardProgress(item);
            committedProgress = currentProgress;
            pendingSnapshot = null;
        }
    });

    $effect(() => () => void debounce.flush(true));

    function step(delta: number) {
        const item = options.getItem();
        if (!options.getOnProgress() || !supportsProgressStepper(item)) return;

        const next = nextCardProgress(item, currentProgress, delta);
        if (next === currentProgress) return;

        if (pendingSnapshot === null) pendingSnapshot = committedProgress;

        currentProgress = next;
        error = null;
        debounce.schedule(item.id, next);
    }

    return {
        get value() {
            return currentProgress;
        },
        get error() {
            return error;
        },
        step,
    };
}