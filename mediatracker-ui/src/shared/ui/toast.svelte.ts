import { serverRestart } from "$shared/api/serverRestart.svelte";

export type ToastType = "success" | "info" | "warning" | "error";

/**
 * A custom labelled button (e.g. the keepStatus action). Rendered as a compact icon in
 * the collapsed corner row and as a full text button in the expanded footer.
 */
export interface ToastAction {
  /** Machine id, e.g. "keepStatus"; also picks the collapsed icon glyph. */
  id: string;
  label: string;
  onClick: () => void;
  /** "primary" renders filled, "neutral" (default) renders outlined. */
  kind?: "primary" | "neutral";
}

export interface ToastOptions {
  /** Strict contract: every toast carries a readable headline. */
  title: string;
  /** Strict contract: every toast carries a detailed explanation revealed on expand. */
  description: string;
  type?: ToastType;
  /** Auto-dismiss delay; 0 disables the timer and the countdown bar. */
  durationMs?: number;
  /** Standard "OK" button — confirm and close. */
  showOk?: boolean;
  /** Standard "Undo" button; the callback must persist the revert server-side. */
  undo?: () => void;
  /** Extra custom buttons rendered next to OK/Undo (e.g. keepStatus). */
  actions?: ToastAction[];
  /** Fired only for an explicit user close (X button) — never for auto-expiry,
   *  so a toast whose expiry itself performs an action can safely cancel on X. */
  onClose?: () => void;
}

export interface ToastItem {
  id: string;
  title: string;
  description: string;
  type: ToastType;
  durationMs: number;
  showOk: boolean;
  undo?: () => void;
  actions: ToastAction[];
  onClose?: () => void;
}

const DEFAULT_DURATION_MS = 4000;
const MAX_TOASTS = 5;

class ToastStore {
  items = $state<ToastItem[]>([]);

  show(options: ToastOptions): string {
    const type = options.type ?? "success";
    // During a backend restart the background refresh catches "connection failed" and tries
    // to show an "unexpected error" — that failure is expected, the modal state already
    // shows a spinner.
    if (type === "error" && serverRestart.isRestarting) {
      return "";
    }

    const id = Math.random().toString(36).substring(2, 9);
    const item: ToastItem = {
      id,
      title: options.title,
      description: options.description,
      type,
      durationMs: options.durationMs ?? DEFAULT_DURATION_MS,
      showOk: options.showOk ?? false,
      undo: options.undo,
      actions: options.actions ?? [],
      onClose: options.onClose,
    };
    this.items = [...this.items.slice(-(MAX_TOASTS - 1)), item];
    return id;
  }

  dismiss(id: string) {
    this.items = this.items.filter((t) => t.id !== id);
  }
}

export const toastStore = new ToastStore();

/** Strict-contract toast: `title` and `description` are mandatory at compile time. */
export function showToast(options: ToastOptions): string {
  return toastStore.show(options);
}

export function dismissToast(id: string) {
  toastStore.dismiss(id);
}
