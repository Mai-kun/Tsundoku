export interface PrefetchCache<T> {
  /** Fresh value for `id`, or undefined when absent/expired. Never triggers a fetch. */
  peek(id: string): T | undefined;
  has(id: string): boolean;
  /**
   * Returns the cached value, an already in-flight request for the same `id`,
   * or starts `fetcher` and caches its result. Failures are not cached.
   */
  load(id: string, fetcher: () => Promise<T>): Promise<T>;
  invalidate(id: string): void;
}

export function createPrefetchCache<T>(ttlMs: number): PrefetchCache<T> {
  const entries = new Map<string, { value: T; expiresAt: number }>();
  const inFlight = new Map<string, Promise<T>>();

  function peek(id: string): T | undefined {
    const entry = entries.get(id);
    if (!entry) return undefined;
    if (Date.now() >= entry.expiresAt) {
      entries.delete(id);
      return undefined;
    }
    return entry.value;
  }

  return {
    peek,
    has: (id) => peek(id) !== undefined,
    load(id, fetcher) {
      const cached = peek(id);
      if (cached !== undefined) return Promise.resolve(cached);

      const running = inFlight.get(id);
      if (running) return running;

      const request = fetcher()
        .then((value) => {
          entries.set(id, { value, expiresAt: Date.now() + ttlMs });
          return value;
        })
        .finally(() => {
          inFlight.delete(id);
        });

      inFlight.set(id, request);
      return request;
    },
    invalidate: (id) => {
      entries.delete(id);
    },
  };
}
