<script lang="ts">
  import { Ban, Trash2, X } from "$shared/ui/Icons";
  import Modal from "$shared/ui/Modal.svelte";
  import { updateStatus, errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS } from "$shared/types";
  import {
    getDropReasonsForMediaType,
    type DropReasonOption,
  } from "$entities/media/model/dropReasons";
  import { dropPromptState, type DropPromptTarget } from "./dropReasonPrompt.svelte";

  interface Props {
    target?: DropPromptTarget | null;
    isOpen?: boolean;
    onClose?: () => void;
  }

  let {
    target: explicitTarget = null,
    isOpen: explicitIsOpen,
    onClose: explicitOnClose,
  }: Props = $props();

  const currentTarget = $derived(explicitTarget ?? dropPromptState.target);
  const isOpen = $derived(explicitIsOpen !== undefined ? explicitIsOpen : currentTarget !== null);

  let selectedReason = $state<string | null>(null);
  let notes = $state("");
  let saving = $state(false);
  let saveError = $state<unknown>(null);

  $effect(() => {
    if (currentTarget) {
      selectedReason = currentTarget.dropReason ?? null;
      notes = currentTarget.dropNotes ?? "";
      saveError = null;
    }
  });

  const isRu = $derived(i18n.current === "ru");
  const options = $derived<DropReasonOption[]>(
    currentTarget ? getDropReasonsForMediaType(currentTarget.type, currentTarget.isAnime) : [],
  );

  function close() {
    if (explicitOnClose) {
      explicitOnClose();
    } else {
      dropPromptState.close();
    }
  }

  function handleSkip() {
    if (saving) return;
    close();
  }

  async function handleSave() {
    if (!currentTarget || saving) return;
    saving = true;
    saveError = null;
    try {
      const cleanNotes = notes.trim() || null;
      await updateStatus(currentTarget.id, {
        status: MEDIA_STATUS.dropped,
        dropReason: selectedReason,
        dropNotes: cleanNotes,
      });
      currentTarget.onSaved?.(selectedReason, cleanNotes);
      close();
    } catch (e) {
      saveError = e;
    } finally {
      saving = false;
    }
  }

  async function handleDeleteReason() {
    if (!currentTarget || saving) return;
    saving = true;
    saveError = null;
    try {
      await updateStatus(currentTarget.id, {
        status: MEDIA_STATUS.dropped,
        dropReason: "",
        dropNotes: "",
      });
      currentTarget.onSaved?.(null, null);
      close();
    } catch (e) {
      saveError = e;
    } finally {
      saving = false;
    }
  }

  function toggleReason(key: string) {
    selectedReason = selectedReason === key ? null : key;
  }
</script>

{#if isOpen && currentTarget}
  <Modal {isOpen} onClose={handleSkip} size="md">
    <div class="flex flex-col space-y-5 p-6">
      <!-- Header -->
      <div class="flex items-start justify-between gap-3">
        <div class="flex items-center gap-3">
          <div
            class="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-rose-500/20 bg-rose-500/10 text-rose-400"
          >
            <Ban size={20} aria-hidden="true" />
          </div>
          <div class="min-w-0">
            <h2 class="text-base font-semibold tracking-tight text-white">
              {i18n.t.dropReason.modalTitle}
            </h2>
            <p class="max-w-sm truncate text-xs text-slate-400" title={currentTarget.title}>
              {currentTarget.title}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="tap -mt-2 -mr-2 rounded-lg p-2 text-slate-400 transition hover:bg-white/5 hover:text-white"
          onclick={handleSkip}
          aria-label={i18n.t.dropReason.skip}
        >
          <X size={18} aria-hidden="true" />
        </button>
      </div>

      <!-- Chips container -->
      <div class="space-y-2">
        <div class="flex max-h-56 flex-wrap gap-2 overflow-y-auto pr-1">
          {#each options as option (option.key)}
            {@const active = selectedReason === option.key}
            <button
              type="button"
              class="tap cursor-pointer rounded-lg border px-3 py-1.5 text-xs transition {active
                ? 'border-rose-500/40 bg-rose-500/20 font-medium text-rose-300 ring-1 ring-rose-500/30'
                : 'border-white/[0.08] bg-white/[0.04] text-slate-300 hover:bg-white/[0.08] hover:text-white'}"
              onclick={() => toggleReason(option.key)}
            >
              {isRu ? option.label.ru : option.label.en}
            </button>
          {/each}
        </div>
      </div>

      <!-- Note input -->
      <div class="space-y-1.5">
        <input
          type="text"
          bind:value={notes}
          placeholder={i18n.t.dropReason.notesPlaceholder}
          maxlength={200}
          class="w-full rounded-lg border border-white/[0.08] bg-white/[0.03] px-3.5 py-2 text-xs text-white placeholder-slate-500 focus:border-rose-400/50 focus:ring-1 focus:ring-rose-400/30 focus:outline-none"
          onkeydown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void handleSave();
            }
          }}
        />
      </div>

      {#if saveError}
        <p class="text-xs text-rose-400" role="alert">
          {errorMessage(saveError)}
        </p>
      {/if}

      <!-- Footer actions -->
      <div class="flex items-center justify-between gap-3 border-t border-white/5 pt-1">
        <div>
          {#if currentTarget.dropReason}
            <button
              type="button"
              class="tap inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium text-rose-400/80 transition hover:bg-rose-500/10 hover:text-rose-300"
              onclick={handleDeleteReason}
              disabled={saving}
            >
              <Trash2 size={13} aria-hidden="true" />
              {i18n.t.dropReason.deleteReason}
            </button>
          {/if}
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            class="tap rounded-lg px-3.5 py-1.5 text-xs font-medium text-slate-300 transition hover:bg-white/5 hover:text-white"
            onclick={handleSkip}
            disabled={saving}
          >
            {i18n.t.dropReason.skip}
          </button>
          <button
            type="button"
            class="tap rounded-lg bg-rose-600 px-4 py-1.5 text-xs font-semibold text-white shadow-md transition hover:bg-rose-500 disabled:opacity-50"
            onclick={handleSave}
            disabled={saving}
          >
            {saving ? "..." : i18n.t.dropReason.save}
          </button>
        </div>
      </div>
    </div>
  </Modal>
{/if}
