// Unit check for stale backlog triage: verifies getDaysInactive and isStaleInProgress
// Run with: node --experimental-strip-types checks/staleTriage.check.ts
import assert from "node:assert/strict";
import { getDaysInactive, isStaleInProgress } from "../src/entities/media/model/staleTriage.ts";
import type { MediaItem } from "../src/shared/types/models.ts";

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

// Test 1: getDaysInactive for different dates
const date30 = new Date(Date.now() - 30 * MS_PER_DAY).toISOString();
const date200 = new Date(Date.now() - 200 * MS_PER_DAY).toISOString();
const date50 = new Date(Date.now() - 50 * MS_PER_DAY).toISOString();

assert.equal(getDaysInactive({ lastActivityAt: date30 }), 30, "30 days inactive calculated correctly");
assert.equal(getDaysInactive({ lastActivityAt: date200 }), 200, "200 days inactive calculated correctly");

// Test fallbacks: startedAt, createdAt, and null
assert.equal(getDaysInactive({ lastActivityAt: null, startedAt: date200 }), 200, "fallback to startedAt");
assert.equal(getDaysInactive({ lastActivityAt: null, startedAt: null, createdAt: date200 }), 200, "fallback to createdAt");
assert.equal(getDaysInactive({ lastActivityAt: null, startedAt: null, createdAt: null }), 0, "no date returns 0");

// Test 2: isStaleInProgress at threshold 180 days for InProgress (status 1)
const staleInProgress = createItem({ status: 1, lastActivityAt: date200 });
const freshInProgress = createItem({ status: 1, lastActivityAt: date50 });

assert.equal(isStaleInProgress(staleInProgress, 180), true, "InProgress with 200 days is stale at threshold 180");
assert.equal(isStaleInProgress(freshInProgress, 180), false, "InProgress with 50 days is not stale at threshold 180");

// Test 3: isStaleInProgress for other statuses (status 0: Planned, 2: Completed, 3: OnHold, 4: Dropped)
const planned = createItem({ status: 0, lastActivityAt: date200 });
const completed = createItem({ status: 2, lastActivityAt: date200 });
const onHold = createItem({ status: 3, lastActivityAt: date200 });
const dropped = createItem({ status: 4, lastActivityAt: date200 });

assert.equal(isStaleInProgress(planned, 180), false, "Planned is never stale in progress");
assert.equal(isStaleInProgress(completed, 180), false, "Completed is never stale in progress");
assert.equal(isStaleInProgress(onHold, 180), false, "OnHold is not stale in progress");
assert.equal(isStaleInProgress(dropped, 180), false, "Dropped is not stale in progress");

// Test 4: Different threshold days
assert.equal(isStaleInProgress(staleInProgress, 90), true, "200 days is stale at 90 days threshold");
assert.equal(isStaleInProgress(staleInProgress, 365), false, "200 days is not stale at 365 days threshold");

console.log("STALE TRIAGE CHECK OK - all assertions passed.");
