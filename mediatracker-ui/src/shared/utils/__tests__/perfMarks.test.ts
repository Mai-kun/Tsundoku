import { describe, it, expect } from "vitest";
import { markStart, markEnd } from "../perfMarks";

describe("perfMarks", () => {
  it("records marks and measures duration into window.__tsundokuPerf", () => {
    // Setup mock window for test environment
    const mockWindow: any = {};
    (globalThis as any).window = mockWindow;

    markStart("test:basic");
    for (let i = 0; i < 10000; i++) {
      Math.sqrt(i);
    }
    const duration = markEnd("test:basic");

    expect(typeof duration).toBe("number");
    expect(duration).toBeGreaterThanOrEqual(0);
    expect(mockWindow.__tsundokuPerf?.["test:basic"]).toBe(duration);

    const entries = performance.getEntriesByName("test:basic", "measure");
    expect(entries.length).toBeGreaterThanOrEqual(1);
    expect(entries[entries.length - 1].duration).toBe(duration);
  });
});
