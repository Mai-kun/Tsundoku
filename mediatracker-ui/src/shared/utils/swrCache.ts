export interface SwrCache<T> {
  /** Last known payload for `key`, or undefined when the view has never loaded. */
  peek(key: string): T | undefined;
  set(key: string, value: T): void;
  invalidate(key: string): void;
}

/**
 * Module-level snapshot cache for stale-while-revalidate views: a view paints the
 * previous payload instantly on mount and refetches in the background. Keyed, so one
 * cache holds every tab (per category on the library screen).
 */
export function createSwrCache<T>(): SwrCache<T> {
  const entries = new Map<string, T>();

  return {
    peek: (key) => entries.get(key),
    set: (key, value) => {
      entries.set(key, value);
    },
    invalidate: (key) => {
      entries.delete(key);
    },
  };
}
