<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { BookOpen, Pencil } from "$shared/ui/Icons.svelte";

    interface Props {
        notes: string | null;
        onEdit: () => void;
    }

    let { notes, onEdit }: Props = $props();
    let hasNotes = $derived(Boolean(notes?.trim()));
</script>

{#if hasNotes}
    <section class="space-y-2 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5">
        <header class="flex items-center justify-between gap-3">
            <h2 class="flex min-w-0 items-center gap-2 text-sm font-semibold text-ink">
                <BookOpen size={16} class="shrink-0 text-muted" />
                {i18n.t.detail.yourNotes}
            </h2>
            <button class="flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs text-muted transition hover:bg-white/[0.05] hover:text-ink" onclick={onEdit}>
                <Pencil size={13} />{i18n.t.detailModal.edit}
            </button>
        </header>
        <p class="whitespace-pre-line text-sm leading-relaxed text-[var(--color-ink-dim)]">{notes}</p>
    </section>
{:else}
    <button class="w-full cursor-pointer rounded-xl border border-dashed border-white/10 p-4 text-center text-sm text-muted transition hover:bg-white/[0.02] hover:text-ink" onclick={onEdit}>
        {i18n.t.detail.addNoteHint}
    </button>
{/if}
