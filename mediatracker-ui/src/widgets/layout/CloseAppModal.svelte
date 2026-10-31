<script lang="ts">
  import { invoke } from "@tauri-apps/api/core";
  import { i18n } from "$shared/i18n/index.svelte";
  import { writeOnCloseAction } from "$shared/utils/tauri";

  type CloseChoice = "minimize_to_tray" | "close_gui" | "exit_all";

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let choice = $state<CloseChoice>("minimize_to_tray");
  let remember = $state(false);
  let isApplying = $state(false);

  async function apply() {
    isApplying = true;
    if (remember) {
      writeOnCloseAction(choice);
    }
    try {
      await invoke("close_action", { action: choice });
    } catch (error) {
      console.error("close_action failed:", error);
    } finally {
      isApplying = false;
      onClose();
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
          choice === "minimize_to_tray"
            ? "border-indigo-500/60 bg-indigo-500/15 ring-1 ring-indigo-500/30"
            : "border-white/10 bg-white/[0.02] hover:border-white/20"
        }`}
      >
        <input type="radio" bind:group={choice} value="minimize_to_tray" class="sr-only" />
        <span
          class={`mt-0.5 h-4 w-4 shrink-0 rounded-full border transition ${
            choice === "minimize_to_tray" ? "border-4 border-indigo-400" : "border-white/25"
          }`}
        ></span>
        <span>
          <span class="block text-sm font-semibold text-white">
            {i18n.t.closeAppModal.minimizeTitle}
          </span>
          <span class="text-muted mt-0.5 block text-xs leading-snug">
            {i18n.t.closeAppModal.minimizeDescription}
          </span>
        </span>
      </label>

      <label
        class={`flex cursor-pointer items-start gap-3 rounded-xl border p-3.5 transition ${
          choice === "close_gui"
            ? "border-indigo-500/60 bg-indigo-500/15 ring-1 ring-indigo-500/30"
            : "border-white/10 bg-white/[0.02] hover:border-white/20"
        }`}
      >
        <input type="radio" bind:group={choice} value="close_gui" class="sr-only" />
        <span
          class={`mt-0.5 h-4 w-4 shrink-0 rounded-full border transition ${
            choice === "close_gui" ? "border-4 border-indigo-400" : "border-white/25"
          }`}
        ></span>
        <span>
          <span class="block text-sm font-semibold text-white">
            {i18n.t.closeAppModal.closeGuiTitle}
          </span>
          <span class="text-muted mt-0.5 block text-xs leading-snug">
            {i18n.t.closeAppModal.closeGuiDescription}
          </span>
        </span>
      </label>

      <label
        class={`flex cursor-pointer items-start gap-3 rounded-xl border p-3.5 transition ${
          choice === "exit_all"
            ? "border-indigo-500/60 bg-indigo-500/15 ring-1 ring-indigo-500/30"
            : "border-white/10 bg-white/[0.02] hover:border-white/20"
        }`}
      >
        <input type="radio" bind:group={choice} value="exit_all" class="sr-only" />
        <span
          class={`mt-0.5 h-4 w-4 shrink-0 rounded-full border transition ${
            choice === "exit_all" ? "border-4 border-indigo-400" : "border-white/25"
          }`}
        ></span>
        <span>
          <span class="block text-sm font-semibold text-white">
            {i18n.t.desktop.exitAll}
          </span>
          <span class="text-muted mt-0.5 block text-xs leading-snug">
            {i18n.t.desktop.exitAllDesc}
          </span>
        </span>
      </label>
    </div>

    <label class="mt-4 flex cursor-pointer items-center gap-2.5 text-xs text-slate-300">
      <input
        type="checkbox"
        bind:checked={remember}
        class="h-4 w-4 cursor-pointer rounded border-white/20 bg-white/5 accent-indigo-500"
      />
      {i18n.t.closeAppModal.remember}
    </label>

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
        onclick={apply}
      >
        {i18n.t.closeAppModal.apply}
      </button>
    </div>
  </div>
</div>
