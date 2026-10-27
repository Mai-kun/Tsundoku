import { describe, it, expect } from "vitest";
import { createPrefetchCache } from "../prefetchCache";

describe("prefetchCache", () => {
  it("deduplicates concurrent fetches for the same key", async () => {
    const cache = createPrefetchCache<number>(1000);
    let calls = 0;
    const fetch = () => {
      calls += 1;
      return new Promise<number>((resolve) => setTimeout(() => resolve(42), 10));
    };

    const [a, b] = await Promise.all([cache.load("x", fetch), cache.load("x", fetch)]);
    expect(calls).toBe(1);
    expect(a).toBe(42);
    expect(b).toBe(42);

    await cache.load("x", fetch);
    expect(calls).toBe(1);
    expect(cache.peek("x")).toBe(42);
  });

  it("refetches when TTL expires", async () => {
    const cache = createPrefetchCache<number>(-1);
    let calls = 0;
    const fetch = async () => ++calls;
    expect(await cache.load("y", fetch)).toBe(1);
    expect(await cache.load("y", fetch)).toBe(2);
  });

  it("retries failed fetches without caching error", async () => {
    const cache = createPrefetchCache<number>(1000);
    let calls = 0;
    const failing = async () => {
      calls += 1;
      throw new Error("boom");
    };

    await expect(cache.load("z", failing)).rejects.toThrow("boom");
    await expect(cache.load("z", failing)).rejects.toThrow("boom");
    expect(calls).toBe(2);
    expect(cache.has("z")).toBe(false);
  });

  it("clears entry on invalidate()", async () => {
    const cache = createPrefetchCache<string>(1000);
    let calls = 0;
    const fetch = async () => `v${++calls}`;
    expect(await cache.load("w", fetch)).toBe("v1");
    cache.invalidate("w");
    expect(cache.has("w")).toBe(false);
    expect(await cache.load("w", fetch)).toBe("v2");
  });
});
