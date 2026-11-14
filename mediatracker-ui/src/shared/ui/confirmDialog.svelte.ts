/**
 * Replaces every native `window.confirm()` with an in-app Obsidian Dark modal rendered
 * dead-center through the shared Modal shell. Each action carries a memory key: when the
 * user ticks one of the two mutually exclusive remember checkboxes, the decision is stored
 * in localStorage and the same action is replayed silently next time.
 */

const MEMORY_KEY = "tsundoku_confirm_memory";
const HOUR_MS = 3600_000;

export type ConfirmRemember = "none" | "forever" | "hour";

interface ConfirmMemoryEntry {
  decision: "confirmed" | "cancelled";
  scope: "forever" | "hour";
  /** Present for the hourly scope only; the entry is stale once `Date.now()` passes it. */
  expiresAt?: number;
}

type ConfirmMemoryMap = Record<string, ConfirmMemoryEntry>;

export interface ConfirmRequest {
  /** Memory key binding the decision to the action, e.g. "delete-media". */
  key: string;
  title: string;
  /** Optional extra context line; omitted for short one-line questions. */
  description?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Danger renders the confirm button in the destructive rose palette. */
  danger?: boolean;
}

interface PendingConfirm extends ConfirmRequest {
  resolve: (confirmed: boolean) => void;
}

function readMemory(): ConfirmMemoryMap {
  if (typeof localStorage === "undefined") return {};
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(MEMORY_KEY) ?? "{}");
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return parsed as ConfirmMemoryMap;
  } catch {
    return {};
  }
}

function writeMemory(memory: ConfirmMemoryMap): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(MEMORY_KEY, JSON.stringify(memory));
  } catch {
    // Storage full / disabled: the dialog simply asks again next time.
  }
}

class ConfirmDialogStore {
  /** The request currently showing its modal; null while nothing asks. */
  current = $state<PendingConfirm | null>(null);
  /** Mirror of the stored decisions so the Settings reset button can show what is kept. */
  memoryVersion = $state(0);

  /** Resolves immediately from memory when the action is remembered, otherwise opens the modal. */
  request(options: ConfirmRequest): Promise<boolean> {
    const memory = readMemory();
    const entry = memory[options.key];
    if (entry) {
      const expired = entry.scope === "hour" && (entry.expiresAt ?? 0) <= Date.now();
      if (!expired) {
        return Promise.resolve(entry.decision === "confirmed");
      }
      delete memory[options.key];
      writeMemory(memory);
      this.memoryVersion += 1;
    }
    return new Promise((resolve) => {
      // One question at a time: any racing second request queues behind the live one.
      this.current = { ...options, resolve };
    });
  }

  /** User picked a button inside the modal: persist the memory choice, then settle. */
  settle(confirmed: boolean, remember: ConfirmRemember): void {
    const pending = this.current;
    this.current = null;
    if (!pending) return;

    if (remember !== "none") {
      const memory = readMemory();
      memory[pending.key] =
        remember === "forever"
          ? { decision: confirmed ? "confirmed" : "cancelled", scope: "forever" }
          : {
              decision: confirmed ? "confirmed" : "cancelled",
              scope: "hour",
              expiresAt: Date.now() + HOUR_MS,
            };
      writeMemory(memory);
      this.memoryVersion += 1;
    }
    pending.resolve(confirmed);
  }

  /** Backdrop click / Esc counts as cancel; never writes memory. */
  cancel(): void {
    const pending = this.current;
    this.current = null;
    pending?.resolve(false);
  }

  /** Settings escape hatch: drops every remembered decision so dialogs ask again. */
  clearMemory(): number {
    const memory = readMemory();
    const count = Object.keys(memory).length;
    if (count > 0) {
      writeMemory({});
      this.memoryVersion += 1;
    }
    return count;
  }

  /** How many actions currently hold a remembered decision (for the Settings row hint). */
  rememberedCount(): number {
    const memory = readMemory();
    const now = Date.now();
    return Object.values(memory).filter(
      (entry) => entry.scope === "forever" || (entry.expiresAt ?? 0) > now,
    ).length;
  }
}

export const confirmDialog = new ConfirmDialogStore();

/** Fire-and-await confirmation: `if (!(await confirmAction({...}))) return;` */
export function confirmAction(options: ConfirmRequest): Promise<boolean> {
  return confirmDialog.request(options);
}
