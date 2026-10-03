<script lang="ts">
    import { Check, Layers, Minus, Pencil, Plus, Trash2, X } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MangaMedia, MangaVolume } from "$shared/types";
    import {
        isVolumeDone,
        volumeCurrent,
        volumePercent,
        volumeProgressLabel,
        volumeTotal,
    } from "$widgets/media-detail/createVolumeController.svelte";

    interface Props {
        media: MangaMedia;
        volumes: readonly MangaVolume[];
        busy: string;
        onAdd: () => void;
        onGenerate: () => void;
        onStep: (volume: MangaVolume, delta: number) => void;
        onEdit: (volume: MangaVolume) => void;
        onDelete: (volume: MangaVolume) => void;
        onMarkComplete: (volume: MangaVolume) => void;
        onUnmarkComplete: (volume: MangaVolume) => void;
    }

    let {
        media,
        volumes,
        busy,
        onAdd,
        onGenerate,
        onStep,
        onEdit,
        onDelete,
        onMarkComplete,
        onUnmarkComplete,
    }: Props = $props();

    const remaining = $derived(
        media.totalVolumes ? media.totalVolumes - volumes.length : 0,
    );
</script>

<section class="space-y-4">
    <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-[var(--color-panel-line)] p-3.5"
    >
        <div class="flex items-center gap-2">
            <Layers size={16} class="text-[var(--color-accent-soft)]" />
            <h3 class="text-sm font-bold text-white">
                {i18n.t.detail.tabVolumes}
            </h3>
            <span
                class="rounded-full bg-white/10 px-2 py-0.5 text-xs font-semibold text-[var(--color-accent-soft)]"
            >
                {volumes.length}
            </span>
        </div>

        <div class="flex items-center gap-2">
            {#if remaining > 0}
                <button
                    type="button"
                    class="inline-flex h-8 items-center gap-1.5 rounded-md bg-white/10 px-3 text-xs font-semibold text-white transition hover:bg-white/20 disabled:opacity-50"
                    disabled={Boolean(busy)}
                    onclick={onGenerate}
                >
                    <Plus size={13} aria-hidden="true" />
                    {i18n.t.detail.addVolume} ({remaining})
                </button>
            {/if}
            <button
                type="button"
                class="inline-flex h-8 items-center gap-1.5 rounded-md bg-[var(--color-accent)] px-3 text-xs font-semibold text-white transition hover:bg-[var(--color-accent-bright)] disabled:opacity-50"
                disabled={Boolean(busy)}
                onclick={onAdd}
            >
                <Plus size={13} aria-hidden="true" />
                {i18n.t.detail.addVolume}
            </button>
        </div>
    </div>

    {#if volumes.length === 0}
        <div
            class="rounded-xl border border-white/[0.08] bg-[color-mix(in_oklab,var(--color-panel-line)_40%,transparent)] p-8 text-center space-y-3"
        >
            <Layers size={36} class="mx-auto text-muted/60" />
            <p class="text-sm text-muted">
                {i18n.current === "ru"
                    ? "Тома этого манги пока не отслеживаются."
                    : "No volumes tracked yet for this manga."}
            </p>
            <button
                type="button"
                class="inline-flex items-center gap-1.5 rounded-lg bg-[var(--color-accent)] px-4 py-2 text-xs font-semibold text-white transition hover:bg-[var(--color-accent-bright)]"
                disabled={Boolean(busy)}
                onclick={onAdd}
            >
                <Plus size={14} aria-hidden="true" />
                {i18n.t.detail.addVolume}
            </button>
        </div>
    {:else}
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {#each volumes as vol (vol.id)}
                {@const isDone = isVolumeDone(vol)}
                {@const current = volumeCurrent(vol)}
                {@const total = volumeTotal(vol)}
                {@const percent = volumePercent(vol)}
<div
                    class="rounded-xl border border-white/[0.08] bg-[var(--color-panel-line)] p-4 space-y-3 shadow-sm hover:border-white/[0.14] transition"
                >
                    <div class="flex items-start justify-between gap-2">
                        <div class="min-w-0">
                            <h4 class="text-sm font-bold text-white truncate">
                                {vol.title || `Volume ${vol.volumeNumber}`}
                            </h4>
                        </div>
                        {#if isDone}
                            <span
                                class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 text-xs font-bold text-emerald-300"
                            >
                                <Check size={12} stroke-width={2.5} />
                                {i18n.t.status.completed}
                            </span>
                        {:else}
                            <span class="text-xs font-semibold tabular-nums text-white">
                                {volumeProgressLabel(vol)}
                            </span>
                        {/if}
                    </div>

                    <div class="space-y-1">
                        <div class="flex justify-between text-[11px] text-muted">
                            <span>{i18n.t.detail.volumeProgress}</span>
                            <span>{percent.toFixed(0)}%</span>
                        </div>
                        <div class="h-2 w-full overflow-hidden rounded-full bg-black/40">
                            <div
                                class="h-full rounded-full bg-gradient-to-r from-[var(--color-accent)] to-[var(--color-info-soft)] transition-all duration-300"
                                style={`width: ${percent}%`}
                            ></div>
                        </div>
                    </div>

                    <div
                        class="flex items-center justify-between gap-2 pt-1 border-t border-white/[0.06]"
                    >
                        <div
                            class="flex h-8 items-center rounded-lg bg-[var(--color-field)] border border-white/[0.08]"
                        >
                            <button
                                type="button"
                                class="grid h-full w-8 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                                disabled={current <= 0 || Boolean(busy)}
                                onclick={() => onStep(vol, -1)}
                            >
                                <Minus size={13} aria-hidden="true" />
                            </button>
                            <span
                                class="px-2.5 text-xs font-semibold tabular-nums text-white"
                                >{current}</span
                            >
                            <button
                                type="button"
                                class="grid h-full w-8 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                                disabled={(total > 0 && current >= total) ||
                                    Boolean(busy)}
                                onclick={() => onStep(vol, 1)}
                            >
                                <Plus size={13} aria-hidden="true" />
                            </button>
                        </div>

                        <div class="flex items-center gap-1.5">
                            <button
                                type="button"
                                class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/[0.08] px-2 text-xs font-semibold text-muted hover:bg-white/10 hover:text-white transition"
                                onclick={() => onEdit(vol)}
                                title={i18n.current === "ru"
                                    ? "Изменить том"
                                    : "Edit volume"}
                            >
                                <Pencil size={12} aria-hidden="true" />
                            </button>
                            <button
                                type="button"
                                class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/[0.08] px-2 text-xs font-semibold text-muted hover:bg-rose-500/20 hover:text-rose-400 transition"
                                onclick={() => onDelete(vol)}
                                title={i18n.current === "ru"
                                    ? "Удалить том"
                                    : "Delete volume"}
                            >
                                <Trash2 size={12} aria-hidden="true" />
                            </button>
{#if !isDone}
                                <button
                                    type="button"
                                    class="inline-flex h-8 items-center gap-1 rounded-lg bg-emerald-500/15 border border-emerald-500/25 px-2.5 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/25 disabled:opacity-50"
                                    disabled={Boolean(busy)}
                                    onclick={() => onMarkComplete(vol)}
                                >
                                    <Check size={13} aria-hidden="true" />
                                    {i18n.t.detail.markRead}
                                </button>
                            {:else}
                                <button
                                    type="button"
                                    class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/[0.08] px-2.5 text-xs font-semibold text-muted transition hover:bg-white/10 hover:text-white disabled:opacity-50"
                                    disabled={Boolean(busy)}
                                    onclick={() => onUnmarkComplete(vol)}
                                >
                                    <X size={13} aria-hidden="true" />
                                    {i18n.t.detail.unmarkRead}
                                </button>
                            {/if}
                        </div>
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</section>