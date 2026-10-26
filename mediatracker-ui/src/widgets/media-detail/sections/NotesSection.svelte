<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { BookOpen, Pencil } from "$shared/ui/Icons.svelte";

  interface Props {
    notes: string | null;
    onEdit: () => void;
    isBook?: boolean;
  }

  let { notes, onEdit }: Props = $props();
  let hasNotes = $derived(Boolean(notes?.trim()));

  const title = $derived(i18n.t.detail.yourNotes);
  const placeholder = $derived(i18n.t.detail.notesPlaceholder);
</script>

{#if hasNotes}
  <section
    class="space-y-2 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
  >
    <header class="flex items-center justify-between gap-3">
      <h2 class="text-ink flex min-w-0 items-center gap-2 text-sm font-semibold">
        <BookOpen size={16} class="text-muted shrink-0" />
        {title}
      </h2>
      <button
        type="button"
        class="text-muted hover:text-ink flex shrink-0 cursor-pointer items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs transition hover:bg-white/[0.05]"
        onclick={onEdit}
      >
        <Pencil size={13} />{i18n.t.detailModal.edit}
      </button>
    </header>
    <p class="text-sm leading-relaxed whitespace-pre-line text-[var(--color-ink-dim)]">{notes}</p>
  </section>
{:else}
  <button
    type="button"
    class="group flex min-h-[140px] w-full cursor-pointer flex-col justify-center rounded-xl border border-dashed border-white/10 bg-[var(--color-panel-line)]/50 p-5 text-left transition hover:border-white/20 hover:bg-white/[0.03]"
    onclick={onEdit}
  >
    <span
      class="text-muted group-hover:text-ink mb-3 flex size-10 items-center justify-center rounded-xl bg-white/[0.05] transition"
    >
      <Pencil size={18} />
    </span>
    <span class="text-ink text-sm font-semibold">{title}</span>
    <span class="text-muted/70 mt-2 text-sm leading-relaxed">{placeholder}</span>
  </button>
{/if}
