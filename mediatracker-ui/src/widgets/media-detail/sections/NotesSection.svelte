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
    <section class="space-y-2 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
        <header class="flex items-center justify-between gap-3">
            <h2 class="flex min-w-0 items-center gap-2 text-sm font-semibold text-ink">
                <BookOpen size={16} class="shrink-0 text-muted" />
                {title}
            </h2>
            <button class="flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs text-muted transition hover:bg-white/[0.05] hover:text-ink cursor-pointer" onclick={onEdit}>
                <Pencil size={13} />{i18n.t.detailModal.edit}
            </button>
        </header>
        <p class="whitespace-pre-line text-sm leading-relaxed text-[var(--color-ink-dim)]">{notes}</p>
    </section>
{:else}
    <button type="button" class="group flex min-h-[140px] w-full cursor-pointer flex-col justify-center rounded-xl border border-dashed border-white/10 bg-[var(--color-panel-line)]/50 p-5 text-left transition hover:border-white/20 hover:bg-white/[0.03]" onclick={onEdit}>
        <span class="mb-3 flex size-10 items-center justify-center rounded-xl bg-white/[0.05] text-muted transition group-hover:text-ink">
            <Pencil size={18} />
        </span>
        <span class="text-sm font-semibold text-ink">{title}</span>
        <span class="mt-2 text-sm leading-relaxed text-muted/70">{placeholder}</span>
    </button>
{/if}
