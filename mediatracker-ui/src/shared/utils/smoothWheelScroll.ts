/**
 * Chrome-style animated wheel scrolling for WebKitGTK (Tauri on Linux).
 *
 * Chromium animates every wheel notch through the compositor, so scrolling
 * glides over ~100-150 ms even on a discrete mouse wheel. WebKitGTK has no
 * such animation and scrolls synchronously on the main thread: each notch is
 * an instant jump, which reads as harsh, stuttery motion next to a browser on
 * the same machine — no env flag changes that, the behavior simply does not
 * exist in the engine. This module replicates the browser feel at the app
 * level: wheel input sets an animation target, a requestAnimationFrame loop
 * eases `scrollTop` toward it, and the virtual grid keeps working because the
 * TanStack virtualizer only reads scroll events.
 */

/** Pixels per DOM_DELTA_LINE "line"; matches Chromium's default wheel step. */
const LINE_HEIGHT = 40;
/** Pixel deltas below this are trackpad streams — they are already smooth. */
const NOTCH_MIN_PX = 10;
/** Time constant of the exponential approach; lower = snappier. */
const TAU_MS = 70;
/** Animation stops when the remaining distance is under this fraction of a px. */
const SNAP_PX = 0.5;
/** An external scroll differing from our last write by more than this rebases. */
const EXTERNAL_SCROLL_PX = 1.5;

/** Only WebKitGTK inside Tauri lacks native smooth wheel scrolling. */
export function shouldSmoothScrollWheel(): boolean {
  if (typeof window === "undefined") return false;
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return false;
  // Tauri v2 injects this global into every webview it hosts.
  if (!("__TAURI_INTERNALS__" in window)) return false;
  const ua = navigator.userAgent;
  return /linux/i.test(ua) && !/android|mobile/i.test(ua);
}

/**
 * Takes over wheel scrolling of `scroller`. Returns a cleanup function; a
 * no-op when the platform should keep native scrolling (browsers, WebView2,
 * reduced motion).
 */
export function installSmoothWheelScroll(scroller: HTMLElement): () => void {
  if (!shouldSmoothScrollWheel()) return () => {};

  let rafId = 0;
  let lastTs = 0;
  let current = scroller.scrollTop;
  let target = current;

  const maxScroll = () => scroller.scrollHeight - scroller.clientHeight;
  const clamp = (value: number) => Math.max(0, Math.min(value, maxScroll()));

  const tick = (ts: number) => {
    const dt = lastTs ? Math.min(64, ts - lastTs) : 16;
    lastTs = ts;
    const diff = target - current;
    if (Math.abs(diff) <= SNAP_PX) {
      current = target;
      scroller.scrollTop = current;
      rafId = 0;
      lastTs = 0;
      return;
    }
    current += diff * (1 - Math.exp(-dt / TAU_MS));
    scroller.scrollTop = current;
    rafId = requestAnimationFrame(tick);
  };

  const animate = () => {
    if (!rafId) rafId = requestAnimationFrame(tick);
  };

  const stop = () => {
    if (rafId) {
      cancelAnimationFrame(rafId);
      rafId = 0;
      lastTs = 0;
    }
  };

  /** Nested scrollables (episode lists, modals) keep native handling. */
  const hasNestedScroller = (event: WheelEvent): boolean => {
    for (const node of event.composedPath()) {
      if (node === scroller) return false;
      if (!(node instanceof HTMLElement)) continue;
      const overflowY = getComputedStyle(node).overflowY;
      if (/(auto|scroll)/.test(overflowY) && node.scrollHeight > node.clientHeight + 1) {
        return true;
      }
    }
    return false;
  };

  const onWheel = (event: WheelEvent) => {
    // Zoom and horizontal pans stay native.
    if (event.ctrlKey || event.deltaX !== 0) return;
    if (hasNestedScroller(event)) return;
    event.preventDefault();

    if (event.deltaMode === WheelEvent.DOM_DELTA_PAGE) {
      target += event.deltaY * scroller.clientHeight;
    } else {
      let dy = event.deltaY;
      if (event.deltaMode === WheelEvent.DOM_DELTA_LINE) dy *= LINE_HEIGHT;
      if (event.deltaMode === WheelEvent.DOM_DELTA_PIXEL && Math.abs(event.deltaY) < NOTCH_MIN_PX) {
        // Trackpad stream: apply directly, an animation would add latency.
        current = target = clamp(target + dy);
        scroller.scrollTop = current;
        return;
      }
      target += dy;
    }
    target = clamp(target);
    animate();
  };

  // Our own per-frame writes land exactly on `current`; anything else means an
  // external scroll (keyboard, scrollbar drag, programmatic) — cancel the
  // animation and rebase, otherwise the next notch would snap back to a stale
  // target.
  const onScroll = () => {
    if (rafId && Math.abs(scroller.scrollTop - current) > EXTERNAL_SCROLL_PX) {
      stop();
    }
    if (!rafId) {
      current = target = scroller.scrollTop;
    }
  };

  scroller.addEventListener("wheel", onWheel, { passive: false });
  scroller.addEventListener("scroll", onScroll, { passive: true });
  return () => {
    stop();
    scroller.removeEventListener("wheel", onWheel);
    scroller.removeEventListener("scroll", onScroll);
  };
}
