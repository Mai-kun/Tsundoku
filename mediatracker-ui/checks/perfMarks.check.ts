import assert from "node:assert/strict";
import { markStart, markEnd } from "../src/shared/utils/perfMarks.ts";

console.log("[check:perf-marks] Running Web Performance API mark/measure verification...");

// Setup mock window for Node.js environment
const mockWindow: Window = {} as unknown as Window;
(globalThis as unknown as { window: Window }).window = mockWindow;

// 1. Basic measure test
markStart("test:basic");
// brief synchronous delay
for (let i = 0; i < 100000; i++) {
  Math.sqrt(i);
}
const duration = markEnd("test:basic");

assert(typeof duration === "number", "markEnd should return a number duration");
assert(duration >= 0, `duration should be non-negative, got ${duration}`);
assert.equal(
  mockWindow.__tsundokuPerf?.["test:basic"],
  duration,
  "Duration must be saved into window.__tsundokuPerf",
);

// 2. Measure exists in performance timeline
const entries = performance.getEntriesByName("test:basic", "measure");
assert(entries.length >= 1, "Measure entry should be registered in performance timeline");
assert.equal(entries[entries.length - 1].duration, duration, "Timeline entry duration must match returned value");

// 3. Graceful handling of unmatched end mark
const unmatchedDuration = markEnd("test:nonexistent");
assert.equal(unmatchedDuration, null, "Unmatched markEnd should safely return null");

console.log("✅ [check:perf-marks] All performance mark tests passed successfully.");
