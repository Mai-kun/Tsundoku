/**
 * True while the backend is restarting after a storage-mode switch or an update apply.
 * The window survives the restart by design, so background refreshes hit a short window
 * of network errors: those failures are expected and must not surface as error toasts.
 */
class ServerRestartState {
  isRestarting = $state(false);
}

export const serverRestart = new ServerRestartState();

const PROBE_URL = () => `/api/settings/storage?t=${Date.now()}`;

async function probe(timeoutMs: number): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(PROBE_URL(), { cache: "no-store", signal: controller.signal });
    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Survives the backend restart end-to-end and only returns control once the NEW process
 * is already responding. Two-phase scheme — otherwise there is a race: the first successful
 * poll could catch the dying old server, the page would reload too early and collect errors.
 *
 * Phase 1: wait for the current server to actually go down (connection refused). If it
 * never goes down within the limit — no restart was scheduled, reload right away.
 * Phase 2: wait for the new process to start responding.
 *
 * The calling modal keeps its loader (saving/isSavingStorage) the whole time; the reload
 * happens only after this returns — the page starts on a live server, with no errors.
 */
export async function waitForBackendRestart(restartScheduled: boolean): Promise<void> {
  serverRestart.isRestarting = true;
  try {
    if (!restartScheduled) {
      return;
    }

    // Phase 1: the current server must go down (graceful shutdown fits in ~2 s).
    const downDeadline = Date.now() + 5000;
    let wentDown = false;
    while (Date.now() < downDeadline) {
      if (!(await probe(400))) {
        wentDown = true;
        break;
      }
      await sleep(150);
    }
    if (!wentDown) {
      // No restart happened (or it already finished before the first poll).
      return;
    }

    // Phase 2: the new process comes up and starts responding.
    const upDeadline = Date.now() + 20_000;
    while (Date.now() < upDeadline) {
      if (await probe(800)) {
        return;
      }
      await sleep(150);
    }
    // The server never came up within 20 s: reload anyway and let the UI show its own state.
  } finally {
    serverRestart.isRestarting = false;
  }
}
