<script lang="ts">
  import { Check, Pencil, Plus, Quote, Trash2, X } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import ModuleCard from "./ModuleCard.svelte";
  import type { QuoteDraft } from "./moduleTypes";

  /**
   * Block 3 — standalone editor for quotes and excerpts. The list lives entirely in the bindable
   * prop; nothing is written to the API here, so the caller serialises it into `quotesJson` on
   * save (or renders the same module read-only elsewhere).
   */
  interface Props {
    quotes: QuoteDraft[];
  }

  let { quotes = $bindable([]) }: Props = $props();

  let isAdding = $state(false);
  let newText = $state("");
  let newContext = $state("");
  let editingId = $state<string | null>(null);
  let editText = $state("");
  let editContext = $state("");

  function addQuote() {
    const text = newText.trim();
    if (!text) return;
    quotes = [
      ...quotes,
      {
        id: crypto.randomUUID(),
        text,
        pageOrContext: newContext.trim() || undefined,
        createdAt: new Date().toISOString(),
      },
    ];
    newText = "";
    newContext = "";
    isAdding = false;
  }

  function startEditing(quote: QuoteDraft) {
    editingId = quote.id;
    editText = quote.text;
    editContext = quote.pageOrContext ?? "";
  }

  function commitEditing() {
    if (!editingId) return;
    const text = editText.trim();
    if (!text) return;
    quotes = quotes.map((quote) =>
      quote.id === editingId
        ? { ...quote, text, pageOrContext: editContext.trim() || undefined }
        : quote,
    );
    editingId = null;
  }

  function cancelEditing() {
    editingId = null;
    editText = "";
    editContext = "";
  }

  function removeQuote(id: string) {
    quotes = quotes.filter((quote) => quote.id !== id);
    if (editingId === id) cancelEditing();
  }
</script>

<ModuleCard title={i18n.t.createModal.modules.quotes} count={quotes.length}>
  {#snippet icon()}
    <Quote size={15} aria-hidden="true" />
  {/snippet}
  <div class="space-y-3">
    {#if isAdding}
      <div class="space-y-2.5 rounded-lg border border-amber-400/20 bg-black/25 p-3">
        <textarea
          class="text-ink placeholder:text-muted/60 min-h-[80px] w-full resize-y rounded-lg border border-white/10 bg-black/20 p-2.5 text-sm leading-relaxed outline-none focus:border-amber-400/60"
          placeholder={i18n.t.detail.quotesPlaceholder}
          bind:value={newText}></textarea>
        <div class="flex items-center justify-end gap-2">
          <input
            type="text"
            class="text-ink placeholder:text-muted/60 h-8 min-w-0 flex-1 rounded-lg border border-white/10 bg-black/20 px-2.5 text-xs outline-none focus:border-amber-400/60"
            placeholder={i18n.t.detail.quotesContextPlaceholder}
            bind:value={newContext}
          />
          <button
            type="button"
            class="text-muted hover:text-ink rounded-lg px-2.5 py-1.5 text-xs transition"
            onclick={() => {
              isAdding = false;
              newText = "";
              newContext = "";
            }}
          >
            {i18n.t.detail.quotesCancel}
          </button>
          <button
            type="button"
            class="rounded-lg bg-amber-400/90 px-3 py-1.5 text-xs font-semibold text-black transition hover:bg-amber-300 disabled:cursor-not-allowed disabled:opacity-50"
            disabled={!newText.trim()}
            onclick={addQuote}
          >
            {i18n.t.detail.quotesSave}
          </button>
        </div>
      </div>
    {:else}
      <button
        type="button"
        class="text-accent-soft hover:text-ink flex items-center gap-1.5 rounded-lg border border-dashed border-white/10 px-3 py-2 text-xs font-semibold transition hover:border-amber-400/30"
        onclick={() => (isAdding = true)}
      >
        <Plus size={14} aria-hidden="true" />
        {i18n.t.detail.quotesAdd}
      </button>
    {/if}

    {#if quotes.length === 0}
      <p class="text-muted px-1 text-sm">{i18n.t.detail.quotesEmpty}</p>
    {:else}
      <ul class="space-y-2">
        {#each quotes as quote (quote.id)}
          <li class="group rounded-lg border border-amber-400/20 bg-amber-500/[0.02] p-3 transition hover:border-amber-400/40">
            {#if editingId === quote.id}
              <div class="space-y-2.5">
                <textarea
                  class="text-ink min-h-[70px] w-full resize-y rounded-lg border border-white/10 bg-black/20 p-2.5 text-sm leading-relaxed outline-none focus:border-amber-400/60"
                  bind:value={editText}></textarea>
                <div class="flex items-center gap-2">
                  <input
                    type="text"
                    class="text-ink placeholder:text-muted/60 h-8 min-w-0 flex-1 rounded-lg border border-white/10 bg-black/20 px-2.5 text-xs outline-none focus:border-amber-400/60"
                    placeholder={i18n.t.detail.quotesContextPlaceholder}
                    bind:value={editContext}
                  />
                  <button
                    type="button"
                    class="text-muted hover:text-ink grid size-7 place-items-center rounded-lg transition"
                    aria-label={i18n.t.detail.quotesCancel}
                    onclick={cancelEditing}
                  >
                    <X size={14} aria-hidden="true" />
                  </button>
                  <button
                    type="button"
                    class="grid size-7 place-items-center rounded-lg bg-amber-400/90 text-black transition hover:bg-amber-300 disabled:opacity-50"
                    disabled={!editText.trim()}
                    aria-label={i18n.t.detail.quotesSave}
                    onclick={commitEditing}
                  >
                    <Check size={14} aria-hidden="true" />
                  </button>
                </div>
              </div>
            {:else}
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0 flex-1 space-y-1">
                  <p class="text-slate-200 font-serif text-sm leading-relaxed italic">
                    <span class="text-amber-400/40">“</span>{quote.text}<span
                      class="text-amber-400/40"
                      >”</span
                    >
                  </p>
                  {#if quote.pageOrContext}
                    <p class="text-amber-300 text-xs font-medium">— {quote.pageOrContext}</p>
                  {/if}
                </div>
                <div class="flex shrink-0 items-center gap-1">
                  <button
                    type="button"
                    class="text-muted hover:text-ink grid size-7 place-items-center rounded-lg opacity-0 transition focus-visible:opacity-100 group-hover:opacity-100"
                    aria-label={i18n.t.detailModal.edit}
                    onclick={() => startEditing(quote)}
                  >
                    <Pencil size={13} aria-hidden="true" />
                  </button>
                  <button
                    type="button"
                    class="text-muted hover:text-rose-300 grid size-7 place-items-center rounded-lg opacity-0 transition focus-visible:opacity-100 group-hover:opacity-100"
                    aria-label={i18n.t.common.delete}
                    onclick={() => removeQuote(quote.id)}
                  >
                    <Trash2 size={13} aria-hidden="true" />
                  </button>
                </div>
              </div>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</ModuleCard>
