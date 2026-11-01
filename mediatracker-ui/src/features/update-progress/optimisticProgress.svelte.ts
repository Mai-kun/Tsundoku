import { SvelteMap } from "svelte/reactivity";
import type { MediaItem } from "$shared/types";
import { readCardProgress, writeCardProgress } from "$entities/media/model/progressRules";

/**
 * Single source of truth for progress the user has stepped but the server has
 * not confirmed yet. Cards and the detail page both write here, so a value
 * stepped on a card survives the trip into the detail screen (and back) even
 * though the underlying items are separate objects and the debounce has not
 * fired. SvelteMap keeps the reads reactive for consumers that derive from it.
 */
interface OptimisticEntry {
  value: number;
  at: number;
}

/** The debounce sends after 3s; a network round-trip cannot outlive this much
 *  more. Entries older than the TTL are dropped on read — a keepalive flush on
 *  tab close never reports back, and without a cap a stale override would
 *  freeze the UI on a value the server may have rejected. */
const ENTRY_TTL_MS = 15_000;

const entries = new SvelteMap<string, OptimisticEntry>();

/** Records (or updates, while the debounce keeps resetting) the local value. */
export function applyOptimisticProgress(id: string, value: number): void {
  entries.set(id, { value, at: Date.now() });
}

/** Server confirmed `confirmed`: drop the override, or re-base it if a newer
 *  step landed while the request was in flight. */
export function resolveOptimisticProgress(id: string, confirmed: number): void {
  const entry = entries.get(id);
  if (!entry) return;
  if (entry.value === confirmed) {
    entries.delete(id);
  } else {
    entries.set(id, { value: entry.value, at: Date.now() });
  }
}

/** The request failed: the optimistic value has nothing backing it anymore. */
export function clearOptimisticProgress(id: string): void {
  entries.delete(id);
}

export function peekOptimisticProgress(id: string): number | null {
  const entry = entries.get(id);
  if (!entry) return null;
  if (Date.now() - entry.at > ENTRY_TTL_MS) {
    entries.delete(id);
    return null;
  }
  return entry.value;
}

/**
 * Anti-rollback merge for incoming DB data. While a local step is pending
 * (debounce ticking or request in flight), refetched data must not drag the
 * visible number back to the stale server value in either direction, so the
 * optimistic value is held until the server reports the same number — which
 * also clears the override, since the server has caught up.
 */
export function reconcileProgress(id: string, incoming: number): number {
  const optimistic = peekOptimisticProgress(id);
  if (optimistic === null) return incoming;
  if (optimistic === incoming) {
    entries.delete(id);
    return incoming;
  }
  return optimistic;
}

/**
 * Bulk {@link reconcileProgress} for a refetched list before it replaces the
 * rendered items (`allItems = found`): any item with a live optimistic step
 * keeps that step on the incoming object instead of snapping back to the
 * server value. Items the server has caught up with drop their override here,
 * so the entries never outlive the confirmation.
 */
export function reconcileListProgress(items: readonly MediaItem[]): void {
  for (const item of items) {
    if (!entries.has(item.id)) continue;
    const reconciled = reconcileProgress(item.id, readCardProgress(item));
    if (reconciled !== readCardProgress(item)) {
      writeCardProgress(item, reconciled);
    }
  }
}
