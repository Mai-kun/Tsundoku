import { untrack } from "svelte";
import { SvelteMap } from "svelte/reactivity";
import { MEDIA_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
import { updateStatus } from "$shared/api/api";
import { createProgressDebounce } from "$shared/utils/progressDebounce";
import { toastStore } from "$shared/ui/toast.svelte";
import { i18n } from "$shared/i18n/index.svelte";
import { updateCachedDetailProgress } from "$features/prefetch-details/mediaDetailPrefetch";
import {
  applyOptimisticProgress,
  clearOptimisticProgress,
  reconcileProgress,
  resolveOptimisticProgress,
} from "$features/update-progress/optimisticProgress.svelte";
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
      // field (e.g. the auto status-flip swaps the object mid-step): keep it
      // instead of snapping back to the stale snapshot.
      if (!hasOptimisticProgress) {
        currentProgress = reconcileProgress(item.id, readCardProgress(item));
        committedProgress = readCardProgress(item);
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
    // An idle start (progress 0 / Planned) defers the flip behind a 10s
    // interactive toast instead of switching the status on the first click.
    if (item.status !== MEDIA_STATUS.inProgress) {
      scheduleDeferredInProgress(item, currentProgress === 0, options.getOnStatusChange?.());
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

/* ---------- Deferred Planned → InProgress (10s interactive toast) ---------- */

const DEFERRED_STATUS_MS = 10000;

interface PendingStatus {
  item: MediaItem;
  onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
  timer: ReturnType<typeof setTimeout>;
  toastId: string;
}

const pendingStatuses = new SvelteMap<string, PendingStatus>();

function applyPendingStatus(id: string) {
  const pending = pendingStatuses.get(id);
  if (!pending) return;
  pendingStatuses.delete(id);
  clearTimeout(pending.timer);
  transitionToInProgress(pending.item, pending.onStatusChange);
  toastStore.dismiss(pending.toastId);
}

/** Cancels a pending status flip: the item stays in its current status (Planned). */
export function cancelPendingStatus(id: string) {
  const pending = pendingStatuses.get(id);
  if (!pending) return;
  pendingStatuses.delete(id);
  clearTimeout(pending.timer);
  toastStore.dismiss(pending.toastId);
}

/* ---------- Flush on exit (F5 / tab hide / window close) ----------
   The debounced progress PUTs register their own keepalive handlers in
   progressDebounce; the 10s status flips must flush the same way, or a
   refresh silently drops the InProgress change the countdown was carrying. */
function flushPendingStatuses() {
  for (const pending of [...pendingStatuses.values()]) {
    pendingStatuses.delete(pending.item.id);
    clearTimeout(pending.timer);
    toastStore.dismiss(pending.toastId);
    // keepalive lets the request outlive the page; the api client cannot.
    void fetch(`/api/media/${pending.item.id}/status`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: MEDIA_STATUS.inProgress }),
      keepalive: true,
    }).catch(() => {});
  }
}

let statusLifecycleRegistered = false;
function registerStatusLifecycleHandlers() {
  if (statusLifecycleRegistered || typeof window === "undefined") return;
  statusLifecycleRegistered = true;
  window.addEventListener("beforeunload", flushPendingStatuses);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flushPendingStatuses();
  });
}
registerStatusLifecycleHandlers();

/**
 * Schedules the InProgress flip 10s out behind an interactive toast with a
 * countdown bar, an Apply button and a Cancel path (Undo / X). Only an idle
 * start (progress was 0) or a Planned title defers; anything else flips
 * immediately as before. Clicking + / - on an already pending title keeps the
 * original countdown running instead of interrupting or restarting it.
 */
export function scheduleDeferredInProgress(
  item: MediaItem,
  wasIdleStart: boolean,
  onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void,
): void {
  if (item.status === MEDIA_STATUS.inProgress) return;
  if (!wasIdleStart && item.status !== MEDIA_STATUS.planned) {
    transitionToInProgress(item, onStatusChange);
    return;
  }
  if (pendingStatuses.has(item.id)) return;

  const toastId = toastStore.showInteractive({
    message: i18n.t.toast.statusPending(item.title.trim() || item.type),
    type: "warning",
    durationMs: DEFERRED_STATUS_MS,
    showTimerProgress: true,
    action: {
      label: i18n.t.toast.applyNow,
      onClick: () => applyPendingStatus(item.id),
    },
    cancelAction: {
      label: i18n.t.common.cancel,
      onClick: () => cancelPendingStatus(item.id),
    },
    // X click counts as an explicit cancel; the 10s expiry does not (it applies).
    onClose: () => cancelPendingStatus(item.id),
  });
  const timer = setTimeout(() => applyPendingStatus(item.id), DEFERRED_STATUS_MS);
  pendingStatuses.set(item.id, { item, onStatusChange, timer, toastId });
}
