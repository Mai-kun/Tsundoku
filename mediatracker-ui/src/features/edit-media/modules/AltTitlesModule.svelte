<script lang="ts">
  import { Pencil, Plus, Tag, Trash2, X } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import ModuleCard from "./ModuleCard.svelte";

  /**
   * Block 4 — alternative titles as a clean, human-readable list. A quick input on top splits the
   * pasted text on `/`, `,` and newlines, so `Title 1 / Title 2` lands as two entries; every
   * existing entry is its own editable row that can be fixed or removed in place. The caller owns
   * the list and decides how to persist it.
   */
  interface Props {
    altTitles: string[];
  }

  let { altTitles = $bindable([]) }: Props = $props();

  let quickInput = $state("");
  let editingIndex = $state<number | null>(null);
  let editingValue = $state("");

  function commitQuickInput() {
    const parts = quickInput
      .split(/[/,,\n]/)
      .map((value) => value.trim())
      .filter(Boolean);
    if (parts.length === 0) return;
    // Keep the list clean: re-adding an existing title (even pasted in a batch) is a no-op.
    const existing = new Set(altTitles.map((value) => value.toLowerCase()));
    const fresh = parts.filter((value) => !existing.has(value.toLowerCase()));
    if (fresh.length > 0) altTitles = [...altTitles, ...fresh];
    quickInput = "";
  }

  function removeTitle(index: number) {
    altTitles = altTitles.filter((_, i) => i !== index);
    if (editingIndex === index) editingIndex = null;
  }

  function startEditing(index: number) {
    editingIndex = index;
    editingValue = altTitles[index];
  }

  function commitEditing() {
    if (editingIndex === null) return;
    const trimmed = editingValue.trim();
    if (trimmed && trimmed !== altTitles[editingIndex]) {
      const next = [...altTitles];
      next[editingIndex] = trimmed;
      altTitles = next;
    }
    editingIndex = null;
    editingValue = "";
  }

  function cancelEditing() {
    editingIndex = null;
    editingValue = "";
  }
</script>

<ModuleCard title={i18n.t.createModal.modules.altTitles} count={altTitles.length}>
  {#snippet icon()}
    <Tag size={15} aria-hidden="true" />
  {/snippet}
  <div class="space-y-3">
    <!-- No inner <form>: the editor renders inside the modal's big form, and Chromium refuses
         implicit submission for nested forms, so Enter is handled on the input itself. -->
    <div class="flex gap-2">
      <input
        class="bg-field placeholder:text-muted h-9 min-w-0 flex-1 rounded-lg border border-white/10 px-3 text-sm font-normal outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
        bind:value={quickInput}
        onkeydown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            commitQuickInput();
          }
        }}
        placeholder={i18n.t.createModal.altTitlesModule.quickAddPlaceholder}
      />
      <button
        type="button"
        class="tap bg-accent hover:bg-accent-hover grid size-9 shrink-0 place-items-center rounded-lg text-white transition disabled:cursor-not-allowed disabled:opacity-50"
        disabled={!quickInput.trim()}
        aria-label={i18n.t.createModal.altTitlesModule.add}
        title={i18n.t.createModal.altTitlesModule.add}
        onclick={commitQuickInput}
      >
        <Plus size={16} aria-hidden="true" />
      </button>
    </div>

    {#if altTitles.length === 0}
      <p class="text-muted px-1 text-sm">{i18n.t.createModal.altTitlesModule.empty}</p>
    {:else}
      <ul class="space-y-1.5">
        {#each altTitles as altTitle, index (index)}
          <li class="group flex items-center gap-2 rounded-lg border border-white/[0.06] bg-white/[0.03] px-2.5 py-1.5">
            {#if editingIndex === index}
              <input
                class="bg-field text-ink h-7 min-w-0 flex-1 rounded-md border border-indigo-500/60 px-2 text-sm font-normal outline-none"
                bind:value={editingValue}
                onkeydown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    commitEditing();
                  } else if (event.key === "Escape") {
                    cancelEditing();
                  }
                }}
                onblur={commitEditing}
                aria-label={i18n.t.createModal.fields.altTitles}
              />
              <button
                type="button"
                class="text-muted hover:text-ink grid size-6 shrink-0 place-items-center rounded-md transition"
                aria-label={i18n.t.common.cancel}
                onmousedown={(event) => event.preventDefault()}
                onclick={cancelEditing}
              >
                <X size={13} aria-hidden="true" />
              </button>
            {:else}
              <span class="text-ink min-w-0 flex-1 truncate text-sm">{altTitle}</span>
              <button
                type="button"
                class="text-muted hover:text-ink grid size-6 shrink-0 place-items-center rounded-md opacity-0 transition focus-visible:opacity-100 group-hover:opacity-100"
                aria-label={i18n.t.detailModal.edit}
                title={i18n.t.detailModal.edit}
                onclick={() => startEditing(index)}
              >
                <Pencil size={13} aria-hidden="true" />
              </button>
              <button
                type="button"
                class="text-muted hover:text-rose-300 grid size-6 shrink-0 place-items-center rounded-md opacity-0 transition focus-visible:opacity-100 group-hover:opacity-100"
                aria-label={i18n.t.common.delete}
                title={i18n.t.common.delete}
                onclick={() => removeTitle(index)}
              >
                <Trash2 size={13} aria-hidden="true" />
              </button>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</ModuleCard>
