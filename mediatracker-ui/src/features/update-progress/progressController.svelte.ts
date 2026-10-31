import { untrack } from "svelte";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
import { updateStatus } from "$shared/api/api";
import { createProgressDebounce } from "$shared/utils/progressDebounce";
import {
  nextCardProgress,
  readCardProgress,
  supportsProgressStepper,
  writeCardProgress,
} from "$entities/media/model/progressRules";

export interface CardProgressState {
  readonly value: number;
  readonly error: unknown;
  step(delta: number): void;
}

export interface CardProgressOptions {
  /** Accessor, not a value: the item prop is replaced when the grid refetches. */
  getItem: () => MediaItem;
  getOnProgress: () => ((id: string, currentProgress: number) => Promise<void>) | undefined;
  getOnProgressCommitted: () => () => void;
  getOnStatusChange?: () => ((item: MediaItem, newStatus: MediaStatus) => void) | undefined;
}

export function createCardProgress(options: CardProgressOptions): CardProgressState {
  let trackedItem: MediaItem | null = null;
  let currentProgress = $state(untrack(() => readCardProgress(options.getItem())));
  let committedProgress = $state(untrack(() => currentProgress));
  let pendingSnapshot = $state<number | null>(null);
  let error = $state<unknown>(null);
  /** True while a scheduled step is newer than the tracked item's progress field. */
  let hasOptimisticProgress = false;

  const debounce = createProgressDebounce({
    send: (id, value) => (options.getOnProgress() ?? (async () => {}))(id, value),
    buildRequest: (id, value) => ({
      url: `/api/media/${id}/progress`,
      body: { currentProgress: value },
    }),
    onCommitted: (value) => {
      committedProgress = value;
      hasOptimisticProgress = false;
      if (currentProgress === value) options.getOnProgressCommitted()();
    },
    onError: (failure) => {
      currentProgress = pendingSnapshot ?? committedProgress;
      committedProgress = currentProgress;
      pendingSnapshot = null;
      hasOptimisticProgress = false;
      error = failure;
    },
  });

  $effect(() => {
    const item = options.getItem();
    if (item !== trackedItem) {
      trackedItem = item;
      // An in-flight optimistic step is newer than the replaced item's progress
      // field (e.g. the auto status-flip swaps the object mid-step): keep it
      // instead of snapping back to the stale snapshot.
      if (!hasOptimisticProgress) {
        currentProgress = readCardProgress(item);
        committedProgress = currentProgress;
      }
      pendingSnapshot = null;
    }
  });

  $effect(() => () => void debounce.flush(true));

  function step(delta: number) {
    const item = options.getItem();
    if (!options.getOnProgress() || !supportsProgressStepper(item)) return;

    const next = nextCardProgress(item, currentProgress, delta);
    if (next === currentProgress) return;

    // Write through to the raw item BEFORE the status flip below: the flip's
    // parent map spreads this object into a new one, and the spread must carry
    // the stepped progress.
    writeCardProgress(item, next);

    // Stepping a title that is not InProgress implies it is being consumed
    // right now: flip the status, mirroring the badge's optimistic flow.
    if (item.status !== MEDIA_STATUS.inProgress) {
      transitionToInProgress(item, options.getOnStatusChange?.());
    }

    if (pendingSnapshot === null) pendingSnapshot = committedProgress;

    currentProgress = next;
    hasOptimisticProgress = true;
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

/** Optimistically flips the item to InProgress and persists the status change. */
export function transitionToInProgress(
  item: MediaItem,
  onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void,
): void {
  if (item.status === MEDIA_STATUS.inProgress) return;
  item.status = MEDIA_STATUS.inProgress;
  onStatusChange?.(item, MEDIA_STATUS.inProgress);
  void updateStatus(item.id, MEDIA_STATUS.inProgress).catch((failure) => console.error(failure));
}
