<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { closeToTray, exitApp } from "$shared/utils/appExit";

  type CloseChoice = "tray" | "exit";

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let choice = $state<CloseChoice>("tray");
  let isApplying = $state(false);

  async function apply() {
    isApplying = true;
    try {
      if (choice === "exit") {
        await exitApp();
        return;
      }
      closeToTray();
      onClose();
    } finally {
      isApplying = false;
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="fixed inset-0 z-[60] flex items-center justify-center bg-[#090b10]/80 p-4">
  <div
    role="dialog"
    aria-modal="true"
    aria-label={i18n.t.closeAppModal.title}
    class="w-full max-w-md rounded-xl border border-white/10 bg-[#151a26]/95 p-5 shadow-2xl shadow-black/60"
  >
    <h2 class="text-ink text-base font-bold">{i18n.t.closeAppModal.title}</h2>

    <div class="mt-4 space-y-2.5">
      <label
        class={`flex cursor-pointer items-start gap-3 rounded-xl border p-3.5 transition ${
          choice === "tray"
            ? "border-indigo-500/60 bg-indigo-500/15 ring-1 ring-indigo-500/30"
            : "border-white/10 bg-white/[0.02] hover:border-white/20"
        }`}
      >
        <input type="radio" bind:group={choice} value="tray" class="sr-only" />
        <span
          class={`mt-0.5 h-4 w-4 shrink-0 rounded-full border transition ${
            choice === "tray" ? "border-4 border-indigo-400" : "border-white/25"
          }`}
        ></span>
        <span>
          <span class="block text-sm font-semibold text-white">
            {i18n.t.closeAppModal.backgroundTitle}
          </span>
          <span class="text-muted mt-0.5 block text-xs leading-snug">
            {i18n.t.closeAppModal.backgroundDescription}
          </span>
        </span>
      </label>

      <label
        class={`flex cursor-pointer items-start gap-3 rounded-xl border p-3.5 transition ${
          choice === "exit"
            ? "border-rose-500/60 bg-rose-500/15 ring-1 ring-rose-500/30"
            : "border-white/10 bg-white/[0.02] hover:border-white/20"
        }`}
      >
        <input type="radio" bind:group={choice} value="exit" class="sr-only" />
        <span
          class={`mt-0.5 h-4 w-4 shrink-0 rounded-full border transition ${
            choice === "exit" ? "border-4 border-rose-400" : "border-white/25"
          }`}
        ></span>
        <span>
          <span class="block text-sm font-semibold text-white">
            {i18n.t.closeAppModal.exitTitle}
          </span>
          <span class="text-muted mt-0.5 block text-xs leading-snug">
            {i18n.t.closeAppModal.exitDescription}
          </span>
        </span>
      </label>
    </div>

    <div class="mt-5 flex justify-end gap-2.5">
      <button
        type="button"
        class="rounded-lg border border-white/10 px-4 py-2 text-sm font-medium text-slate-300 transition hover:bg-white/5 hover:text-white"
        onclick={onClose}
      >
        {i18n.t.common.cancel}
      </button>
      <button
        type="button"
        disabled={isApplying}
        class="bg-accent hover:bg-accent-hover cursor-pointer rounded-lg px-4 py-2 text-sm font-semibold text-white transition disabled:cursor-not-allowed disabled:opacity-50"
        onclick={() => void apply()}
      >
        {i18n.t.closeAppModal.apply}
      </button>
    </div>
  </div>
</div>
