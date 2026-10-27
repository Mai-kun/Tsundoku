import { describe, it, expect } from "vitest";
import { getDaysInactive, isStaleInProgress } from "../staleTriage";
import type { MediaItem } from "$shared/types/models";

function createItem(opts: {
  status: number;
  lastActivityAt?: string | null;
  startedAt?: string | null;
  createdAt?: string | null;
}): MediaItem {
  return {
    id: "test-item-1",
    type: "game",
    title: "Test Item",
    status: opts.status as any,
    score: null,
    startedAt: opts.startedAt ?? null,
    finishedAt: null,
    lastActivityAt: opts.lastActivityAt ?? null,
    coverUrl: null,
    createdAt: opts.createdAt ?? "2025-01-01T00:00:00Z",
    franchiseId: null,
    franchiseOrder: null,
    platform: "PC",
    hoursPlayed: null,
  };
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

describe("staleTriage", () => {
  it("calculates getDaysInactive for different dates and fallbacks", () => {
    const date30 = new Date(Date.now() - 30 * MS_PER_DAY).toISOString();
    const date200 = new Date(Date.now() - 200 * MS_PER_DAY).toISOString();

    expect(getDaysInactive({ lastActivityAt: date30 })).toBe(30);
    expect(getDaysInactive({ lastActivityAt: date200 })).toBe(200);

    // Fallbacks
    expect(getDaysInactive({ lastActivityAt: null, startedAt: date200 })).toBe(200);
    expect(getDaysInactive({ lastActivityAt: null, startedAt: null, createdAt: date200 })).toBe(
      200,
    );
    expect(getDaysInactive({ lastActivityAt: null, startedAt: null, createdAt: null })).toBe(0);
  });

  it("evaluates isStaleInProgress for InProgress status with threshold", () => {
    const date50 = new Date(Date.now() - 50 * MS_PER_DAY).toISOString();
    const date200 = new Date(Date.now() - 200 * MS_PER_DAY).toISOString();

    const staleInProgress = createItem({ status: 1, lastActivityAt: date200 });
    const freshInProgress = createItem({ status: 1, lastActivityAt: date50 });

    expect(isStaleInProgress(staleInProgress, 180)).toBe(true);
    expect(isStaleInProgress(freshInProgress, 180)).toBe(false);
  });

  it("verifies isStaleInProgress is false for non-in-progress statuses", () => {
    const date200 = new Date(Date.now() - 200 * MS_PER_DAY).toISOString();

    const planned = createItem({ status: 0, lastActivityAt: date200 });
    const completed = createItem({ status: 2, lastActivityAt: date200 });
    const onHold = createItem({ status: 3, lastActivityAt: date200 });
    const dropped = createItem({ status: 4, lastActivityAt: date200 });

    expect(isStaleInProgress(planned, 180)).toBe(false);
    expect(isStaleInProgress(completed, 180)).toBe(false);
    expect(isStaleInProgress(onHold, 180)).toBe(false);
    expect(isStaleInProgress(dropped, 180)).toBe(false);
  });

  it("checks custom thresholds", () => {
    const date200 = new Date(Date.now() - 200 * MS_PER_DAY).toISOString();
    const staleInProgress = createItem({ status: 1, lastActivityAt: date200 });

    expect(isStaleInProgress(staleInProgress, 90)).toBe(true);
    expect(isStaleInProgress(staleInProgress, 365)).toBe(false);
  });
});
