/// 1:1 port of `mediatracker-ui/src/app/clientErrors.ts`.
///
/// "ResizeObserver loop completed with undelivered notifications" (and the
/// legacy "loop limit exceeded") fires whenever an observer callback changes
/// layout mid-frame. It is a browser bookkeeping notice, not an application
/// error — the notification is simply delivered on the next frame — so the
/// client reporter must not forward it to the server. Актуально только для
/// web-канваса.
library;

bool isIgnorableClientError(String message) =>
    message.contains('ResizeObserver loop');
