<script lang="ts">
  import { Archive, FolderOpen, LoaderCircle, Server } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import { getStorageSettings, saveStorageSettings } from "$shared/api/api";
  import type { StorageSettings } from "$shared/types";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  let loading = $state(true);
  let saving = $state(false);
  let mode = $state<"default" | "portable" | "custom">("default");
  let customPath = $state("");
  let settings = $state<StorageSettings | null>(null);
  let isOpen = $state(false);

  onMount(async () => {
    try {
      settings = await getStorageSettings();
      isOpen = Boolean(settings?.isFirstRunSetupRequired);
      if (settings?.mode && (settings.mode === "default" || settings.mode === "portable" || settings.mode === "custom")) {
        mode = settings.mode;
      }
    } catch (e) {
      console.error("Failed to load storage settings:", e);
      isOpen = false;
    } finally {
      loading = false;
    }
  });

  async function waitForServerAndReload() {
    // Wait a brief moment to allow the server to initiate shutdown/restart
    await new Promise((r) => setTimeout(r, 600));

    // Poll for the server to become available again
    for (let i = 0; i < 40; i++) {
      try {
        const res = await fetch("/api/settings/storage?t=" + Date.now(), {
          cache: "no-store",
        });
        if (res.ok) {
          window.location.reload();
          return;
        }
      } catch {
        // Server restarting, wait and retry
      }
      await new Promise((r) => setTimeout(r, 500));
    }

    window.location.reload();
  }

  async function handleSave() {
    if (saving) return;
    if (mode === "custom" && !customPath.trim()) return;

    saving = true;
    try {
      await saveStorageSettings({
        mode,
        customPath: mode === "custom" ? customPath.trim() : "",
        migrateExistingData: false,
      });
      await waitForServerAndReload();
    } catch (e) {
      console.error("Failed to save storage settings:", e);
      saving = false;
    }
  }
</script>

{#if isOpen}
  <Modal {isOpen} onClose={() => {}} closable={false}>
    <div class="p-6">
      <div class="mb-5 flex items-center gap-3">
        <div
          class="grid size-10 shrink-0 place-items-center rounded-xl border border-indigo-500/20 bg-indigo-500/15 text-indigo-400"
        >
          <Server size={20} />
        </div>
        <div>
          <h2 class="text-base font-semibold text-white">
            {i18n.t.settings.storageSetupRequired}
          </h2>
          <p class="mt-0.5 text-xs text-slate-400">
            {i18n.t.settingsModal.storage.description}
          </p>
        </div>
      </div>

      {#if saving}
        <div class="flex flex-col items-center justify-center py-10 text-center">
          <LoaderCircle size={32} class="animate-spin text-indigo-400" />
          <p class="mt-4 text-sm font-medium text-white">
            {i18n.t.settings.storageApplying}
          </p>
        </div>
      {:else if loading}
        <div class="flex min-h-40 items-center justify-center">
          <LoaderCircle size={22} class="animate-spin text-indigo-400" />
        </div>
      {:else}
        <div class="space-y-2.5">
          <label
            class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
              mode === "default"
                ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
            }`}
          >
            <input type="radio" bind:group={mode} value="default" class="sr-only" />
            <Server
              size={18}
              class="shrink-0 {mode === 'default' ? 'text-indigo-400' : 'text-slate-400'}"
            />
            <div class="min-w-0 flex-1">
              <span class="block text-xs font-semibold leading-snug">
                {i18n.t.settings.storageDefault}
              </span>
              <span class="block truncate text-[11px] text-slate-400">
                {settings?.defaultDirectory ?? "~/.local/share/Tsundoku"}
              </span>
            </div>
          </label>

          <label
            class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
              mode === "portable"
                ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
            }`}
          >
            <input type="radio" bind:group={mode} value="portable" class="sr-only" />
            <Archive
              size={18}
              class="shrink-0 {mode === 'portable' ? 'text-indigo-400' : 'text-slate-400'}"
            />
            <div class="min-w-0 flex-1">
              <span class="block text-xs font-semibold leading-snug">
                {i18n.t.settings.storagePortable}
              </span>
              <span class="block truncate text-[11px] text-slate-400">
                {settings?.portableDirectory ?? "./data"}
              </span>
            </div>
          </label>

          <label
            class={`flex cursor-pointer items-center gap-3 rounded-xl border p-3.5 transition ${
              mode === "custom"
                ? "border-indigo-500/60 bg-indigo-500/15 text-white ring-1 ring-indigo-500/30"
                : "border-white/10 bg-white/[0.02] text-slate-300 hover:border-white/20"
            }`}
          >
            <input type="radio" bind:group={mode} value="custom" class="sr-only" />
            <FolderOpen
              size={18}
              class="shrink-0 {mode === 'custom' ? 'text-indigo-400' : 'text-slate-400'}"
            />
            <div class="min-w-0 flex-1">
              <span class="block text-xs font-semibold leading-snug">
                {i18n.t.settings.storageCustom}
              </span>
              <span class="block text-[11px] text-slate-400">
                {i18n.t.settingsModal.storage.customPathLabel}
              </span>
            </div>
          </label>

          {#if mode === "custom"}
            <div class="pt-1" transition:slide={{ duration: 150 }}>
              <input
                type="text"
                bind:value={customPath}
                placeholder={i18n.t.settingsModal.storage.customPathPlaceholder}
                class="bg-field text-ink focus:border-accent-soft focus:ring-accent-soft h-10 w-full rounded-lg border border-white/10 px-3 text-xs transition outline-none focus:ring-1"
              />
            </div>
          {/if}
        </div>

        <div class="mt-6 flex items-center justify-end">
          <button
            type="button"
            disabled={saving || (mode === "custom" && !customPath.trim())}
            onclick={handleSave}
            class="tap inline-flex h-9 cursor-pointer items-center gap-2 rounded-lg bg-indigo-600 px-5 text-xs font-semibold text-white shadow-sm transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <span>{i18n.t.settings.storageConfirm}</span>
          </button>
        </div>
      {/if}
    </div>
  </Modal>
{/if}
