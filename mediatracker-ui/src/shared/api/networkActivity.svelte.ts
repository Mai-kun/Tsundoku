import { untrack } from "svelte";

class NetworkActivity {
  activeRequests = $state(0);
  isLoading = $derived(this.activeRequests > 0);
  #safetyTimer: ReturnType<typeof setTimeout> | null = null;

  begin() {
    untrack(() => {
      this.activeRequests = Math.max(0, this.activeRequests) + 1;
      this.#armSafetyTimer();
    });
  }

  end() {
    untrack(() => {
      this.activeRequests = Math.max(0, this.activeRequests - 1);
      if (this.activeRequests === 0 && this.#safetyTimer !== null) {
        clearTimeout(this.#safetyTimer);
        this.#safetyTimer = null;
      }
    });
  }

  reset() {
    untrack(() => {
      this.activeRequests = 0;
      if (this.#safetyTimer !== null) {
        clearTimeout(this.#safetyTimer);
        this.#safetyTimer = null;
      }
    });
  }

  #armSafetyTimer() {
    if (this.#safetyTimer !== null) {
      clearTimeout(this.#safetyTimer);
    }
    // Safety fallback: network activity indicator never stays active longer than 15s
    this.#safetyTimer = setTimeout(() => {
      this.reset();
    }, 15000);
  }
}

export const networkActivity = new NetworkActivity();
