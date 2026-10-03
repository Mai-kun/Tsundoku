export type ProgressSender = (id: string, value: number) => Promise<void>;

export interface ProgressRequest {
  url: string;
  body: unknown;
}

export interface ProgressDebounceOptions {
  send: ProgressSender;
  buildRequest: (id: string, value: number) => ProgressRequest;
  onCommitted: (value: number) => void;
  onError?: (error: unknown) => void;
  delay?: number;
}

interface PendingProgress {
  id: string;
  value: number;
  buildRequest: (id: string, value: number) => ProgressRequest;
  timer: ReturnType<typeof setTimeout>;
}

const defaultDelay = 375;
const pendingProgress = new Map<symbol, PendingProgress>();
let globalHandlersRegistered = false;

function clearPending(instance: symbol): PendingProgress | null {
  const task = pendingProgress.get(instance);
  if (!task) return null;
  clearTimeout(task.timer);
  pendingProgress.delete(instance);
  return task;
}

async function sendKeepalive(task: PendingProgress) {
  const request = task.buildRequest(task.id, task.value);
  await fetch(request.url, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request.body),
    keepalive: true,
  }).catch(() => {});
}

async function flushPendingKeepalive() {
  const tasks = [...pendingProgress.keys()]
    .map((instance) => clearPending(instance))
    .filter((task): task is PendingProgress => task !== null);

  await Promise.allSettled(tasks.map((task) => sendKeepalive(task)));
}

function registerGlobalHandlers() {
  if (globalHandlersRegistered || typeof window === "undefined") return;
  globalHandlersRegistered = true;
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") void flushPendingKeepalive();
  });
  window.addEventListener("beforeunload", () => void flushPendingKeepalive());
}

export function createProgressDebounce(options: ProgressDebounceOptions) {
  const instance = Symbol("progress-debounce");
  const delay = options.delay ?? defaultDelay;
  let sending = false;
  registerGlobalHandlers();

  async function commit(task: PendingProgress) {
    if (sending) return;
    sending = true;
    try {
      await options.send(task.id, task.value);
      options.onCommitted(task.value);
    } catch (error) {
      options.onError?.(error);
    } finally {
      sending = false;
    }
  }

  function schedule(id: string, value: number) {
    const previous = pendingProgress.get(instance);
    if (previous) clearTimeout(previous.timer);

    const task: PendingProgress = {
      id,
      value,
      buildRequest: options.buildRequest,
      timer: undefined as unknown as ReturnType<typeof setTimeout>,
    };

    task.timer = setTimeout(() => {
      const pending = clearPending(instance);
      if (pending) void commit(pending);
    }, delay);

    pendingProgress.set(instance, task);
  }

  async function flush(keepalive = false) {
    const task = clearPending(instance);
    if (!task) return;

    if (keepalive) {
      await sendKeepalive(task);
      return;
    }

    await commit(task);
  }

  return { schedule, flush };
}
