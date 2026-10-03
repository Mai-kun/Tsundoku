import { untrack } from "svelte";
import type { MediaItem } from "$shared/types";
import { createProgressDebounce } from "$shared/utils/progressDebounce";
import {
    nextCardProgress,
    readCardProgress,
    supportsProgressStepper,
} from "$entities/media/model/progressRules";

export interface CardProgressState {
    readonly value: number;
    readonly error: unknown;
    step(delta: number): void;
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