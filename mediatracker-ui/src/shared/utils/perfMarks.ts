declare global {
  interface Window {
    __tsundokuPerf?: Record<string, number>;
  }
}

export function markStart(name: string): void {
  if (typeof performance === "undefined" || typeof performance.mark !== "function") {
    return;
  }
  try {
    performance.mark(`${name}:start`);
  } catch {
    // ignore performance mark failures
  }
}

export function markEnd(name: string): number | null {
  if (
    typeof performance === "undefined" ||
    typeof performance.mark !== "function" ||
    typeof performance.measure !== "function"
  ) {
    return null;
  }

  try {
    const startMark = `${name}:start`;
    const endMark = `${name}:end`;
    performance.mark(endMark);

    const measure = performance.measure(name, startMark, endMark);
    let duration: number | null = measure ? measure.duration : null;

    if (duration === null || duration === undefined) {
      const entries = performance.getEntriesByName(name, "measure");
      const last = entries[entries.length - 1];
      if (last) {
        duration = last.duration;
      }
    }

    const resolvedDuration = typeof duration === "number" ? duration : null;

    const targetWindow: Window | null =
      typeof window !== "undefined"
        ? window
        : typeof globalThis !== "undefined" && (globalThis as unknown as { window?: Window }).window
          ? (globalThis as unknown as { window: Window }).window
          : null;

    if (targetWindow && resolvedDuration !== null) {
      targetWindow.__tsundokuPerf = targetWindow.__tsundokuPerf || {};
      targetWindow.__tsundokuPerf[name] = resolvedDuration;
    }

    return resolvedDuration;
  } catch {
    return null;
  }
}
