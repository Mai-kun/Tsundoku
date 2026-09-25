export type ProgressSender = (id: string, value: number) => Promise<void>

interface PendingProgress {
  id: string
  value: number
  send: () => ProgressSender
  timer: ReturnType<typeof setTimeout>
}

const pendingProgress = new Map<symbol, PendingProgress>()
let globalHandlersRegistered = false

function clearPending(instance: symbol) {
  const task = pendingProgress.get(instance)
  if (!task) return null
  clearTimeout(task.timer)
  pendingProgress.delete(instance)
  return task
}

function keepaliveRequest(task: PendingProgress) {
  const isSeason = task.send().name === 'setSeasonProgress'
  return {
    url: isSeason ? `/api/seasons/${task.id}/progress` : `/api/media/${task.id}/progress`,
    options: {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(isSeason ? { currentEpisode: task.value } : { currentProgress: task.value }),
      keepalive: true,
    } satisfies RequestInit,
  }
}

async function flushAll() {
  const tasks = [...pendingProgress.keys()].map((instance) => clearPending(instance)).filter((task): task is PendingProgress => task !== null)
  await Promise.allSettled(tasks.map((task) => {
    const request = keepaliveRequest(task)
    return fetch(request.url, request.options)
  }))
}

function registerGlobalHandlers() {
  if (globalHandlersRegistered || typeof window === 'undefined') return
  globalHandlersRegistered = true
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') void flushAll()
  })
  window.addEventListener('beforeunload', () => void flushAll())
}

export function createProgressFlush(send: () => ProgressSender, onCommitted: (value: number) => void, onError: (error: unknown) => void) {
  const instance = Symbol('progress-flush')
  let sending = false
  registerGlobalHandlers()

  async function flushTask(task: PendingProgress) {
    if (sending) return
    sending = true
    try {
      await task.send()(task.id, task.value)
      onCommitted(task.value)
    } catch (error) {
      onError(error)
    } finally {
      sending = false
    }
  }

  async function flush() {
    const task = clearPending(instance)
    if (task) await flushTask(task)
  }

  function schedule(id: string, value: number) {
    const previous = pendingProgress.get(instance)
    if (previous) clearTimeout(previous.timer)
    const task = { id, value, send, timer: undefined as unknown as ReturnType<typeof setTimeout> }
    task.timer = setTimeout(() => {
      clearPending(instance)
      void flushTask(task)
    }, 375)
    pendingProgress.set(instance, task)
  }
  return { schedule, flush }
}
