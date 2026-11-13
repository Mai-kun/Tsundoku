import { toastStore } from "$shared/ui/toast.svelte";
import { i18n } from "$shared/i18n/index.svelte";
import type { MediaItem, MediaStatus } from "$shared/types";

export interface StatusPromotionHandlers {
  /** Undo: progress back to 0 AND status back to the previous one — both persisted. */
  undo: () => void;
  /** Keep-status: progress stays, the previous status is restored — persisted. */
  keepStatus: () => void;
}

/**
 * The 0 → 1 promotion toast (rule 1 of the status contract). Progress just moved from 0 to 1 and
 * the status was auto-flipped to InProgress, so the user gets one interactive notice with three
 * persisted outcomes: OK (accept), Undo (full revert) and Keep status (progress stays).
 */
export function notifyAutoInProgress(
  item: MediaItem,
  previousStatus: MediaStatus,
  handlers: StatusPromotionHandlers,
): void {
  toastStore.show({
    title: i18n.t.toast.statusAutoChangedTitle,
    description: i18n.t.toast.statusAutoChangedDesc(item.title.trim() || item.type),
    type: "info",
    durationMs: 8000,
    showOk: true,
    undo: handlers.undo,
    actions: [{ id: "keepStatus", label: i18n.t.toast.keepStatus, onClick: handlers.keepStatus }],
  });
}
