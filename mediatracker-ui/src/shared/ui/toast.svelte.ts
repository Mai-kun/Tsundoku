export type ToastType = "success" | "warning" | "error";

export interface ToastItem {
  id: string;
  message: string;
  description?: string;
  type: ToastType;
}

class ToastStore {
  items = $state<ToastItem[]>([]);

  show(message: string, type: ToastType = "success", durationMs = 4000, description?: string) {
    const id = Math.random().toString(36).substring(2, 9);
    const item: ToastItem = { id, message, type, description };
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
