import { serverRestart } from "$shared/api/serverRestart.svelte";

export type ToastType = "success" | "warning" | "error";

export interface ToastAction {
  label: string;
  onClick: () => void;
}

export interface ToastItem {
  id: string;
  message: string;
  description?: string;
  type: ToastType;
  /** Primary button rendered to the right of the text (e.g. "Apply"). */
  action?: ToastAction;
  /** Quieter secondary button next to `action` (e.g. "Undo"). */
  cancelAction?: ToastAction;
  /** Renders the 2px countdown bar along the bottom edge of the card. */
  showTimerProgress?: boolean;
  durationMs?: number;
  /** Fired only for an explicit user close (X button) — never for auto-expiry,
   *  so a toast whose expiry itself performs an action can safely cancel on X. */
  onClose?: () => void;
}

class ToastStore {
  items = $state<ToastItem[]>([]);

  show(message: string, type: ToastType = "success", durationMs = 4000, description?: string) {
    // During a backend restart the background refresh catches "connection failed" and tries
    // to show an "unexpected error" — that failure is expected, the modal state already
    // shows a spinner.
    if (type === "error" && serverRestart.isRestarting) {
      return "";
    }
    const id = Math.random().toString(36).substring(2, 9);
    const item: ToastItem = { id, message, type, description, durationMs };
    this.items = [...this.items.slice(-4), item];

    if (durationMs > 0) {
      setTimeout(() => {
        this.dismiss(id);
      }, durationMs);
    }
    return id;
  }

  showInteractive(options: {
    message: string;
    description?: string;
    type?: ToastType;
    durationMs?: number;
    action?: ToastAction;
    cancelAction?: ToastAction;
    showTimerProgress?: boolean;
    onClose?: () => void;
  }) {
    if ((options.type ?? "success") === "error" && serverRestart.isRestarting) {
      return "";
    }
    const id = Math.random().toString(36).substring(2, 9);
    const durationMs = options.durationMs ?? 4000;
    const item: ToastItem = {
      id,
      message: options.message,
      description: options.description,
      type: options.type ?? "success",
      action: options.action,
      cancelAction: options.cancelAction,
      showTimerProgress: options.showTimerProgress,
      durationMs,
      onClose: options.onClose,
    };
    this.items = [...this.items.slice(-4), item];

    if (durationMs > 0) {
      setTimeout(() => {
        this.dismiss(id);
      }, durationMs);
    }
    return id;
  }

  dismiss(id: string) {
    this.items = this.items.filter((t) => t.id !== id);
  }
}

export const toastStore = new ToastStore();

export function showToast(
  message: string,
  type: ToastType = "success",
  durationMs = 4000,
  description?: string,
) {
  return toastStore.show(message, type, durationMs, description);
}

export function dismissToast(id: string) {
  toastStore.dismiss(id);
}
