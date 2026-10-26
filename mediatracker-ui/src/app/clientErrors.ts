// "ResizeObserver loop completed with undelivered notifications" (and the legacy
// "loop limit exceeded") fires whenever an observer callback changes layout
// mid-frame. It is a browser bookkeeping notice, not an application error — the
// notification is simply delivered on the next frame — so the client reporter
// must not forward it to the server.
export function isIgnorableClientError(message: string): boolean {
  return message.includes("ResizeObserver loop");
}
