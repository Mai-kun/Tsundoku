<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Plus, Quote, Trash2 } from "$shared/ui/Icons";
  import { updateMedia, errorMessage } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import type { MediaDetail, MediaQuote } from "$shared/types";

  interface Props {
    media: MediaDetail;
  }

  let { media }: Props = $props();

  function parseQuotes(json?: string | null): MediaQuote[] {
    if (!json) return [];
    try {
      const parsed = JSON.parse(json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  const quotes = $derived(parseQuotes(media.quotesJson));
  let isAdding = $state(false);
  let newText = $state("");
  let newPageOrContext = $state("");
  let isSaving = $state(false);

  function focusOnMount(el: HTMLElement) {
    el.focus();
  }

  async function handleSave() {
    const text = newText.trim();
    if (!text || isSaving) return;

    const newQuote: MediaQuote = {
      id: crypto.randomUUID(),
      text,
      pageOrContext: newPageOrContext.trim() || undefined,
      createdAt: new Date().toISOString(),
    };

    const previousJson = media.quotesJson;
    const nextQuotes = [newQuote, ...quotes];
    const nextJson = JSON.stringify(nextQuotes);

    media.quotesJson = nextJson;
    newText = "";
    newPageOrContext = "";
    isAdding = false;
    isSaving = true;

    try {
      await updateMedia(media.id, { quotesJson: nextJson });
    } catch (err) {
      media.quotesJson = previousJson;
      showToast(errorMessage(err), "error");
    } finally {
      isSaving = false;
    }
  }

  function handleCancel() {
    newText = "";
    newPageOrContext = "";
    isAdding = false;
  }

  async function handleDelete(id: string) {
    const previousJson = media.quotesJson;
    const nextQuotes = quotes.filter((q) => q.id !== id);
    const nextJson = JSON.stringify(nextQuotes);

    media.quotesJson = nextJson;

    try {
      await updateMedia(media.id, { quotesJson: nextJson });
    } catch (err) {
      media.quotesJson = previousJson;
      showToast(errorMessage(err), "error");
    }
  }
</script>

{#if quotes.length > 0 || isAdding}
  <section
    class="space-y-3.5 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
  >
    <header class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-2">
        <Quote size={16} class="shrink-0 text-amber-400" />
        <h2 class="text-xs font-bold tracking-wider text-slate-300 uppercase">
          {i18n.t.detail.quotesTitle}
        </h2>
        {#if quotes.length > 0}
          <span
            class="rounded-full bg-amber-400/10 px-2 py-0.5 text-[11px] font-semibold text-amber-400"
          >
            {quotes.length}
          </span>
        {/if}
      </div>
      <button
        type="button"
        class="text-muted flex size-7 cursor-pointer items-center justify-center rounded-lg border border-white/10 bg-white/[0.04] transition hover:border-amber-400/40 hover:bg-amber-400/10 hover:text-amber-400"
        onclick={() => (isAdding = !isAdding)}
        title={i18n.t.detail.quotesAdd}
        aria-label={i18n.t.detail.quotesAdd}
      >
        <Plus size={15} />
      </button>
    </header>

    {#if isAdding}
      <div class="space-y-3 rounded-lg border border-amber-400/20 bg-black/25 p-3.5 shadow-inner">
        <textarea
          use:focusOnMount
          class="text-ink placeholder:text-muted/60 min-h-[90px] w-full resize-y rounded-lg border border-white/10 bg-black/20 p-3 text-sm leading-relaxed ring-0 outline-none focus:border-amber-400/60 focus:ring-0"
          placeholder={i18n.t.detail.quotesPlaceholder}
          bind:value={newText}></textarea>
        <div class="flex flex-col justify-between gap-2.5 sm:flex-row sm:items-center">
          <input
            type="text"
            class="text-ink placeholder:text-muted/60 w-full rounded-lg border border-white/10 bg-black/20 px-3 py-1.5 text-xs ring-0 outline-none focus:border-amber-400/60 focus:ring-0 sm:max-w-xs"
            placeholder={i18n.t.detail.quotesContextPlaceholder}
            bind:value={newPageOrContext}
          />
          <div class="flex shrink-0 items-center justify-end gap-2">
            <button
              type="button"
              class="text-muted hover:text-ink cursor-pointer rounded-lg px-3 py-1.5 text-xs transition hover:bg-white/[0.05]"
              onclick={handleCancel}
            >
              {i18n.t.detail.quotesCancel}
            </button>
            <button
              type="button"
              class="cursor-pointer rounded-lg bg-amber-400 px-3.5 py-1.5 text-xs font-semibold text-black transition hover:bg-amber-300 disabled:cursor-not-allowed disabled:opacity-50"
              onclick={handleSave}
              disabled={!newText.trim() || isSaving}
            >
              {i18n.t.detail.quotesSave}
            </button>
          </div>
        </div>
      </div>
    {/if}

    <div class="space-y-2.5">
      {#each quotes as quote (quote.id)}
        <div
          class="group relative flex items-center justify-between gap-3 rounded-lg border-l-2 border-amber-400/50 bg-white/[0.02] p-3.5 pl-4 transition hover:border-amber-400 hover:bg-white/[0.04]"
        >
          <div class="min-w-0 flex-1 space-y-1.5">
            <div>
              <span
                class="pointer-events-none mr-1 font-serif text-base leading-none text-amber-400/40 select-none"
                >“</span
              >
              <p class="inline font-serif text-sm leading-relaxed text-slate-200 italic">
                {quote.text}
              </p>
              <span
                class="pointer-events-none ml-1 font-serif text-base leading-none text-amber-400/40 select-none"
                >”</span
              >
            </div>
            {#if quote.pageOrContext}
              <div class="pointer-events-none text-xs font-medium text-amber-300 select-none">
                — {quote.pageOrContext}
              </div>
            {/if}
          </div>
          <button
            type="button"
            class="tap text-muted pointer-events-auto z-10 grid size-8 shrink-0 cursor-pointer place-items-center rounded-lg opacity-0 transition group-hover:opacity-100 hover:bg-rose-500/15 hover:text-rose-400 focus-visible:opacity-100"
            onclick={() => handleDelete(quote.id)}
            title={i18n.t.common.delete}
            aria-label={i18n.t.common.delete}
          >
            <Trash2 size={15} />
          </button>
        </div>
      {/each}
    </div>
  </section>
{:else}
  <button
    type="button"
    class="group flex min-h-[140px] w-full cursor-pointer flex-col justify-center rounded-xl border border-dashed border-white/10 bg-[var(--color-panel-line)]/50 p-5 text-left transition hover:border-amber-400/30 hover:bg-white/[0.03]"
    onclick={() => (isAdding = true)}
  >
    <span
      class="mb-3 flex size-10 items-center justify-center rounded-xl bg-amber-400/10 text-amber-400 transition group-hover:scale-105"
    >
      <Quote size={18} />
    </span>
    <span class="text-xs font-bold tracking-wider text-slate-300 uppercase"
      >{i18n.t.detail.quotesTitle}</span
    >
    <span class="text-muted/70 mt-2 text-sm leading-relaxed">{i18n.t.detail.quotesEmpty}</span>
  </button>
{/if}
