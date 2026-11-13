import { untrack } from "svelte";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
import { setProgress, updateStatus } from "$shared/api/api";
import { createProgressDebounce } from "$shared/utils/progressDebounce";
import { updateCachedDetailProgress } from "$features/prefetch-details/mediaDetailPrefetch";
import { notifyAutoInProgress } from "$features/update-progress/statusPromotionToast.svelte";
import {
  applyOptimisticProgress,
  clearOptimisticProgress,
  reconcileProgress,
  resolveOptimisticProgress,
} from "$features/update-progress/optimisticProgress.svelte";
import {
  nextCardProgress,
  readCardProgress,
  shouldPromoteToInProgress,
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
      resolveOptimisticProgress(trackedItem?.id ?? "", value);
      if (currentProgress === value) options.getOnProgressCommitted()();
    },
    onError: (failure) => {
      currentProgress = pendingSnapshot ?? committedProgress;
      committedProgress = currentProgress;
      pendingSnapshot = null;
      hasOptimisticProgress = false;
      clearOptimisticProgress(trackedItem?.id ?? "");
      error = failure;
    },
  });

  $effect(() => {
    const item = options.getItem();
    if (item !== trackedItem) {
      trackedItem = item;
      // An in-flight optimistic step is newer than the replaced item's progress
      // field (e.g. the status flip swaps the object mid-step): keep it
      // instead of snapping back to the stale snapshot.
      if (!hasOptimisticProgress) {
        currentProgress = reconcileProgress(item.id, readCardProgress(item));
        committedProgress = readCardProgress(item);
      }
      pendingSnapshot = null;
    }
  });

  $effect(() => () => void debounce.flush(true));

  /** Undo: the pending progress=1 write is cancelled, then progress 0 and the previous
   *  status are persisted — exactly what the server stores after an F5. */
  function revertPromotion(target: MediaItem, previousStatus: MediaStatus) {
    debounce.cancel();
    clearOptimisticProgress(target.id);
    pendingSnapshot = null;
    currentProgress = 0;
    committedProgress = 0;
    hasOptimisticProgress = false;
    writeCardProgress(target, 0);
    updateCachedDetailProgress(target.id, 0);
    target.status = previousStatus;
    void setProgress(target.id, 0)
      .then(() => updateStatus(target.id, previousStatus))
      .catch((failure) => console.error(failure));
  }

  /** Keep-status: the progress stays at its new value (persisted explicitly, since the
   *  debounced write is cancelled) and the previous status is restored. */
  function keepProgressOnly(target: MediaItem, previousStatus: MediaStatus, value: number) {
    debounce.cancel();
    pendingSnapshot = null;
    committedProgress = value;
    hasOptimisticProgress = false;
    target.status = previousStatus;
    void setProgress(target.id, value)
      .then(() => resolveOptimisticProgress(target.id, value))
      .catch((failure) => console.error(failure));
    void updateStatus(target.id, previousStatus).catch((failure) => console.error(failure));
  }

  function step(delta: number) {
    const item = options.getItem();
    if (!options.getOnProgress() || !supportsProgressStepper(item)) return;

    const next = nextCardProgress(item, currentProgress, delta);
    if (next === currentProgress) return;

    // Write through to the raw item BEFORE the status flip below: the flip's
    // parent map spreads this object into a new one, and the spread must carry
    // the stepped progress.
    writeCardProgress(item, next);

    // Rule 1 of the status contract: only the exact 0 → 1 step implies the
    // title started and flips to InProgress. Every other step keeps the badge
    // as it is (dropped stays dropped, on hold stays on hold), mirroring the
    // server's single stored rule so an F5 never shows a different status.
    // The flip is announced by an interactive toast: OK accepts, Undo fully
    // reverts (progress 0 + previous status), keep-status keeps the progress
    // and restores the previous status.
    if (shouldPromoteToInProgress(currentProgress, next) && item.status !== MEDIA_STATUS.inProgress) {
      const previousStatus = item.status;
      transitionToInProgress(item, options.getOnStatusChange?.());
      notifyAutoInProgress(item, previousStatus, {
        undo: () => revertPromotion(item, previousStatus),
        keepStatus: () => keepProgressOnly(item, previousStatus, next),
      });
    }

    if (pendingSnapshot === null) pendingSnapshot = committedProgress;

    currentProgress = next;
    hasOptimisticProgress = true;
    error = null;
    applyOptimisticProgress(item.id, next);
    // The cached detail payload (hover prefetch) would otherwise open the
    // detail screen with the pre-step number and snap only after refetch.
    updateCachedDetailProgress(item.id, next);
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
