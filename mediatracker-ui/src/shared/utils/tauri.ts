/**
 * True when the SPA runs inside the Tauri desktop shell (webview with IPC).
 * A plain browser (vite dev server, unit tests, the diag page) has no Tauri
 * internals, so every window-lifecycle integration must bail out on this.
 */
export function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/**
 * localStorage key for the [X]-button behavior. Values: "ask" (default,
 * show the confirmation dialog), "minimize_to_tray", "close_gui", "exit_all".
 */
export const ON_CLOSE_ACTION_KEY = "on_close_action";

export type CloseBehavior = "ask" | "minimize_to_tray" | "close_gui" | "exit_all";

export function readOnCloseAction(): CloseBehavior {
  if (typeof window === "undefined") return "ask";
  const raw = localStorage.getItem(ON_CLOSE_ACTION_KEY);
  return raw === "minimize_to_tray" || raw === "close_gui" || raw === "exit_all" ? raw : "ask";
}

export function writeOnCloseAction(value: CloseBehavior): void {
  try {
    localStorage.setItem(ON_CLOSE_ACTION_KEY, value);
  } catch {
    // Unavailable storage: the dialog simply asks again next time.
  }
}
