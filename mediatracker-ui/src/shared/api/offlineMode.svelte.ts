import { getOfflineMode, setOfflineMode, type OfflineModeResponse } from "./api";

class OfflineModeState {
  isOffline = $state(false);
  hasDatabases = $state(false);
  loading = $state(false);

  async init(): Promise<void> {
    this.loading = true;
    try {
      const res = await getOfflineMode();
      this.isOffline = res.offlineMode;
      this.hasDatabases = res.hasDatabases;
    } catch {
      // Ignore background init failure
    } finally {
      this.loading = false;
    }
  }

  async toggle(enable: boolean): Promise<void> {
    const prev = this.isOffline;
    this.isOffline = enable;
    try {
      const res = await setOfflineMode(enable);
      this.isOffline = res.offlineMode;
    } catch (e) {
      this.isOffline = prev;
      throw e;
    }
  }

  refresh(data: OfflineModeResponse): void {
    this.isOffline = data.offlineMode;
    this.hasDatabases = data.hasDatabases;
  }
}

export const offlineModeState = new OfflineModeState();
