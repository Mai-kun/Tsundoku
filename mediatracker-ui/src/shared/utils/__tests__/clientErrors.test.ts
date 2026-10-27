import { describe, it, expect } from "vitest";
import { isIgnorableClientError } from "$app/clientErrors";

describe("clientErrors", () => {
  it("ignores benign ResizeObserver loop messages", () => {
    expect(
      isIgnorableClientError("ResizeObserver loop completed with undelivered notifications."),
    ).toBe(true);
    expect(isIgnorableClientError("ResizeObserver loop limit exceeded")).toBe(true);
  });

  it("allows real application errors through", () => {
    expect(
      isIgnorableClientError("Uncaught TypeError: Cannot read properties of null (reading 'id')"),
    ).toBe(false);
    expect(isIgnorableClientError("Script error")).toBe(false);
    expect(isIgnorableClientError("")).toBe(false);
  });
});
