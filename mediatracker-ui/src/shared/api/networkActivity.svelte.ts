import { untrack } from "svelte";

class NetworkActivity {
  activeRequests = $state(0);
  isLoading = $derived(this.activeRequests > 0);

  begin() {
    untrack(() => {
      this.activeRequests = Math.max(0, this.activeRequests) + 1;
    });
  }

  end() {
    untrack(() => {
      this.activeRequests = Math.max(0, this.activeRequests - 1);
    });
  }

  reset() {
    untrack(() => {
      this.activeRequests = 0;
    });
  }
}

export const networkActivity = new NetworkActivity();
