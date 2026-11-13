import { shutdownApp } from "$shared/api/api";
import { i18n } from "$shared/i18n/index.svelte";
import { showToast } from "$shared/ui/toast.svelte";

function stoppedScreen(): string {
  return `
<div class="flex h-screen flex-col items-center justify-center bg-[#0d0f14] text-slate-400">
  <p class="text-base font-semibold text-white">${i18n.t.closeAppModal.stoppedTitle}</p>
  <p class="mt-1 text-xs">${i18n.t.closeAppModal.stoppedDescription}</p>
</div>`;
}

/* window.close() only works for windows the browser lets script close. When it
   refuses (Zen/Firefox tab opened by the user), show a stopped screen instead. */
export async function exitApp(): Promise<void> {
  try {
    await shutdownApp();
  } catch {
    // The server may already be down; still close the window.
  }
  window.close();
  setTimeout(() => {
    if (!window.closed) document.body.innerHTML = stoppedScreen();
  }, 400);
}

export function closeToTray(): void {
  window.close();
  setTimeout(() => {
    if (!window.closed)
      showToast({
        title: i18n.t.closeAppModal.backgroundToast,
        description: i18n.t.toast.descActionDone,
      });
  }, 400);
}
