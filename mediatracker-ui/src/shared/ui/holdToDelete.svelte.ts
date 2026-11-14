/**
 * Hold-to-confirm controller: computes `progress` (0..1) every rAF frame while the
 * pointer is held; the caller animates `transform: scaleX(progress)`. An early
 * release rolls the fill back and never completes; a tap shorter than
 * `shortPressMs` shows the hint instead. `destroy()` clears rAF/timers.
 */

export interface HoldToDeleteOptions {
  /** Hold duration in ms (default 1000). */
  durationMs?: number;
  /** Releases shorter than this count as a tap and trigger `onShortPress` (default 300). */
  shortPressMs?: number;
  /** How long the hint stays visible after a short tap (default 1500). */
  hintMs?: number;
  /** Fill rollback duration after an early release (default 220). */
  rollbackMs?: number;
  /** Fired once the hold runs to completion. */
  onComplete: () => void;
  /** Fired when the press ends before `shortPressMs` — the "hold longer" hint moment. */
  onShortPress?: () => void;
  /** Optional gate: when false, press/release events are ignored (e.g. while busy). */
  isEnabled?: () => boolean;
}

const DEFAULT_DURATION_MS = 1000;
const DEFAULT_SHORT_PRESS_MS = 300;
const DEFAULT_HINT_MS = 1500;
const DEFAULT_ROLLBACK_MS = 220;

export class HoldToDeleteController {
  /** Fill ratio 0..1; bind to `transform: scaleX(progress)` with `origin-left`. */
  progress = $state(0);
  holding = $state(false);
  hintVisible = $state(false);

  #options: HoldToDeleteOptions;
  #raf = 0;
  #startedAt = 0;
  #lastFrameAt = 0;
  #hintTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(options: HoldToDeleteOptions) {
    this.#options = options;
  }

  press(): void {
    if (this.#options.isEnabled?.() === false) return;
    if (this.holding) return;
    this.#clearHint();
    this.holding = true;
    this.#startedAt = performance.now();
    this.#lastFrameAt = this.#startedAt;
    cancelAnimationFrame(this.#raf);
    this.#raf = requestAnimationFrame(this.#frame);
  }

  release(): void {
    if (!this.holding) return;
    this.holding = false;
    const heldMs = performance.now() - this.#startedAt;
    if (heldMs < (this.#options.shortPressMs ?? DEFAULT_SHORT_PRESS_MS)) {
      this.#startRollback();
      this.#showHint();
      this.#options.onShortPress?.();
      return;
    }
    this.#startRollback();
  }

  /** Completes immediately — the keyboard path (Enter/Space) skips the hold. */
  completeNow(): void {
    if (this.#options.isEnabled?.() === false) return;
    this.#stop();
    this.#options.onComplete();
  }

  readonly handlers = {
    onpointerdown: () => this.press(),
    onpointerup: () => this.release(),
    onpointerleave: () => this.release(),
    onpointercancel: () => this.release(),
  };

  destroy(): void {
    this.#stop();
    this.#clearHint();
  }

  #frame = (now: number) => {
    const dt = now - this.#lastFrameAt;
    this.#lastFrameAt = now;
    if (this.holding) {
      this.progress = Math.min(1, (now - this.#startedAt) / this.#duration());
      if (this.progress >= 1) {
        this.#stop();
        this.#options.onComplete();
        return;
      }
    } else {
      this.progress = Math.max(0, this.progress - dt / this.#rollback());
      if (this.progress <= 0) return;
    }
    this.#raf = requestAnimationFrame(this.#frame);
  };

  #startRollback(): void {
    cancelAnimationFrame(this.#raf);
    this.#lastFrameAt = performance.now();
    this.#raf = requestAnimationFrame(this.#frame);
  }

  #stop(): void {
    this.holding = false;
    this.progress = 0;
    cancelAnimationFrame(this.#raf);
  }

  #showHint(): void {
    this.#clearHint();
    this.hintVisible = true;
    this.#hintTimer = setTimeout(() => {
      this.hintVisible = false;
      this.#hintTimer = null;
    }, this.#options.hintMs ?? DEFAULT_HINT_MS);
  }

  #clearHint(): void {
    if (this.#hintTimer !== null) {
      clearTimeout(this.#hintTimer);
      this.#hintTimer = null;
    }
    this.hintVisible = false;
  }

  #duration(): number {
    return this.#options.durationMs ?? DEFAULT_DURATION_MS;
  }

  #rollback(): number {
    return this.#options.rollbackMs ?? DEFAULT_ROLLBACK_MS;
  }
}

export function createHoldToDelete(options: HoldToDeleteOptions): HoldToDeleteController {
  return new HoldToDeleteController(options);
}
