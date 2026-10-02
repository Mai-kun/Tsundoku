<script lang="ts">
    import Check from "lucide-svelte/icons/check";
    import Minus from "lucide-svelte/icons/minus";
    import Pencil from "lucide-svelte/icons/pencil";
    import Plus from "lucide-svelte/icons/plus";
    import Trash2 from "lucide-svelte/icons/trash-2";
    import X from "lucide-svelte/icons/x";
    import { i18n } from "$lib/i18n/index.svelte";
    import type { MangaMedia, MangaVolume } from "$lib/types";

    interface Props {
        media: MangaMedia;
        volumes: readonly MangaVolume[];
        volumeBusy: unknown;
        isDone: (volume: MangaVolume) => boolean;
        current: (volume: MangaVolume) => number;
        total: (volume: MangaVolume) => number;
        percent: (volume: MangaVolume) => number;
        progressLabel: (volume: MangaVolume) => string;
        onStepPage: (volume: MangaVolume, delta: number) => Promise<void>;
        onEdit: (volume: MangaVolume) => void;
        onDelete: (volume: MangaVolume) => Promise<void>;
        onMarkComplete: (volume: MangaVolume) => Promise<void>;
        onUnmarkComplete: (volume: MangaVolume) => Promise<void>;
        onAddVolume: () => Promise<void>;
        onGenerateVolumes: () => Promise<void>;
        onOpenVolumesTab: () => void;
    }

    let {
        media,
        volumes,
        volumeBusy,
        isDone,
        current,
        total,
        percent,
        progressLabel,
        onStepPage,
        onEdit,
        onDelete,
        onMarkComplete,
        onUnmarkComplete,
        onAddVolume,
        onGenerateVolumes,
        onOpenVolumesTab,
    }: Props = $props();
</script>

{#if volumes.length > 0}
    <section
        class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
    >
        <div class="flex items-center justify-between gap-3">
            <div>
                <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                    {i18n.t.detail.tabVolumes}
                </h2>
                <p class="text-xs text-muted mt-0.5">
                    {volumes.length}
                    {i18n.t.detail.volumesLabel.toLowerCase()}
                </p>
            </div>
            <div class="flex items-center gap-2">
                <button
                    type="button"
                    class="rounded-lg border border-white/[0.08] bg-surface/50 px-3 py-1.5 text-xs font-medium text-muted transition hover:bg-white/10 hover:text-white"
                    onclick={onOpenVolumesTab}
                >
                    {i18n.t.detail.tabVolumes} →
                </button>
            </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 pt-1">
            {#each volumes as vol (vol.id)}
                {@const done = isDone(vol)}
                {@const value = current(vol)}
                {@const volumeTotal = total(vol)}
<div
                    class="rounded-lg border border-white/[0.08] bg-[var(--color-field)] p-3.5 space-y-2.5"
                >
                    <div class="flex items-center justify-between gap-2">
                        <span class="text-xs font-bold text-white truncate"
                            >{vol.title || `Volume ${vol.volumeNumber}`}</span
                        >
                        {#if done}
                            <span
                                class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-bold text-emerald-300"
                            >
                                <Check size={11} stroke-width={2.5} />
                                OK
                            </span>
                        {:else}
                            <span
                                class="text-xs font-semibold tabular-nums text-white"
                            >
                                {progressLabel(vol)}
                            </span>
                        {/if}
                    </div>

                    <div class="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                        <div
                            class="h-full rounded-full bg-gradient-to-r from-[var(--color-accent)] to-[var(--color-info-soft)] transition-all duration-200"
                            style={`width: ${percent(vol)}%`}
                        ></div>
                    </div>

                    <div class="flex items-center justify-between gap-2 pt-0.5">
                        <div
                            class="flex h-7 items-center rounded-md bg-[var(--color-panel-line)] border border-white/[0.08]"
                        >
                            <button
                                type="button"
                                class="grid h-full w-7 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                                disabled={value <= 0 || Boolean(volumeBusy)}
                                onclick={() => void onStepPage(vol, -1)}
                            >
                                <Minus size={12} />
                            </button>
                            <span
                                class="px-2 text-xs font-semibold tabular-nums text-white"
                                >{value}</span
                            >
                            <button
                                type="button"
                                class="grid h-full w-7 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                                disabled={(volumeTotal > 0 &&
                                        value >= volumeTotal) ||
                                    Boolean(volumeBusy)}
                                onclick={() => void onStepPage(vol, 1)}
                            >
                                <Plus size={12} />
                            </button>
                        </div>
<div class="flex items-center gap-1">
                            <button
                                type="button"
                                class="grid h-7 w-7 place-items-center rounded-md bg-white/5 text-muted transition hover:bg-white/10 hover:text-white"
                                onclick={() => onEdit(vol)}
                                title="Edit volume"
                            >
                                <Pencil size={11} />
                            </button>
                            <button
                                type="button"
                                class="grid h-7 w-7 place-items-center rounded-md bg-white/5 text-muted transition hover:bg-rose-500/20 hover:text-rose-400"
                                onclick={() => void onDelete(vol)}
                                title="Delete volume"
                            >
                                <Trash2 size={11} />
                            </button>

                            {#if !done}
                                <button
                                    type="button"
                                    class="inline-flex h-7 items-center gap-1 rounded-md bg-emerald-500/15 px-2 text-[11px] font-semibold text-emerald-300 transition hover:bg-emerald-500/25 disabled:opacity-50"
                                    disabled={Boolean(volumeBusy)}
                                    onclick={() => void onMarkComplete(vol)}
                                    title={i18n.t.detail.markVolumeComplete}
                                >
                                    <Check size={12} />
                                </button>
                            {:else}
                                <button
                                    type="button"
                                    class="inline-flex h-7 items-center gap-1 rounded-md bg-white/5 px-2 text-[11px] font-semibold text-muted transition hover:bg-white/10 hover:text-white disabled:opacity-50"
                                    disabled={Boolean(volumeBusy)}
                                    onclick={() => void onUnmarkComplete(vol)}
                                    title="Unmark complete"
                                >
                                    <X size={12} />
                                </button>
                            {/if}
                        </div>
                    </div>
                </div>
            {/each}
        </div>
    </section>
{:else if media.totalVolumes && media.totalVolumes > 0}
        <section
            class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
        >
            <div class="flex items-center justify-between gap-3">
                <div>
                    <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                        {i18n.t.detail.tabVolumes}
                    </h2>
                    <p class="text-xs text-muted mt-0.5">
                        {media.totalVolumes}
                        {i18n.t.detail.volumesLabel.toLowerCase()}
                    </p>
                </div>
                <button
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-lg bg-[var(--color-accent)] px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-[var(--color-accent-bright)] disabled:opacity-50"
                    disabled={Boolean(volumeBusy)}
                    onclick={() => void onGenerateVolumes()}
                >
                    <Plus size={13} />
                    {i18n.t.detail.addVolume} ({media.totalVolumes})
                </button>
            </div>
        </section>
    {:else}
        <section
            class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
        >
            <div class="flex items-center justify-between gap-3">
                <div>
                    <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                        {i18n.t.detail.tabVolumes}
                    </h2>
                    <p class="text-xs text-muted mt-0.5">
                        0 {i18n.t.detail.volumesLabel.toLowerCase()}
                    </p>
                </div>
                <button
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-lg bg-[var(--color-accent)] px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-[var(--color-accent-bright)] disabled:opacity-50"
                    disabled={Boolean(volumeBusy)}
                    onclick={() => void onAddVolume()}
                >
                    <Plus size={13} />
                    {i18n.t.detail.addVolume}
                </button>
            </div>
        </section>
    {/if}