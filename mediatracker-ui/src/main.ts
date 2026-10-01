import { mount } from "svelte";
import "./app.css";
import App from "./App.svelte";

function sendClientLog(message: string, stack?: string, url?: string) {
  try {
    fetch("/api/logs/client", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message, stack, url }),
      keepalive: true,
    }).catch(() => {});
  } catch {}
}

window.addEventListener("error", (event) => {
  const message = event.message || "Script error";
  const stack =
    event.error?.stack || `${event.filename}:${event.lineno}:${event.colno}`;
  sendClientLog(message, stack, window.location.href);
});

window.addEventListener("unhandledrejection", (event) => {
  const reason = event.reason;
  const message = reason instanceof Error ? reason.message : String(reason);
  const stack = reason instanceof Error ? reason.stack : undefined;
  sendClientLog(`Unhandled rejection: ${message}`, stack, window.location.href);
});

const app = mount(App, {
  target: document.getElementById("app")!,
});

export default app;
