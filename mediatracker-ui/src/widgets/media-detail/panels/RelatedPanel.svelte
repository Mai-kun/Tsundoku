<script lang="ts">
    import { Bookmark, Check, GitBranch, Image as ImageIcon, Layers, LayoutGrid, Pause, Play, RefreshCw, X } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { MediaItem } from "$shared/types";
    import {
        formatMediaDisplayType,
        relatedStatusClasses,
        statusLabel,
    } from "$widgets/media-detail/detailFormatters";
    import type {
        RelatedEntry,
        RelatedViewMode,
        RelationGroup,
        TimelineEntry,
    } from "$widgets/media-detail/detailTypes";

    interface Props {
        related: readonly RelatedEntry[];
        loading: boolean;
        error: unknown;
        viewMode: RelatedViewMode;
        groups: readonly RelationGroup[];
        timeline: readonly TimelineEntry[];
        onRetry: () => void;
        onSelectViewMode: (mode: RelatedViewMode) => void;
        /** Opens a local item or the preview modal for an external one. */
        onOpen: (entry: RelatedEntry) => void;
    }

    let {
        related,
        loading,
        error,
        viewMode,
        groups,
        timeline,
        onRetry,
        onSelectViewMode,
        onOpen,
    }: Props = $props();

    const VIEWS: ReadonlyArray<{
        mode: RelatedViewMode;
        title: string;
        icon: typeof GitBranch;
    }> = [
        { mode: "grouped", title: i18n.t.detail.viewGrouped, icon: Layers },
        { mode: "timeline", title: i18n.t.detail.viewTimeline, icon: GitBranch },
        { mode: "grid", title: i18n.t.detail.viewGrid, icon: LayoutGrid },
    ];

    function viewClass(mode: RelatedViewMode): string {
        return `grid h-8 w-8 place-items-center rounded-md transition cursor-pointer ${
            viewMode === mode
                ? "bg-accent text-white shadow"
                : "text-slate-400 hover:bg-white/5 hover:text-white"
        }`;
    }
</script>

<section class="space-y-6">
    <div
        class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
        <div>
            <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">
                {i18n.t.detail.relatedTitle}
            </h2>
            <p class="text-xs text-muted">{i18n.t.detail.relatedSubtitle}</p>
        </div>

        {#if related.length > 0}
            <div
                class="inline-flex items-center rounded-lg border border-white/[0.08] bg-[var(--color-track-alt)] p-1 self-start sm:self-auto gap-1"
            >
                {#each VIEWS as view (view.mode)}
                    <button
                        type="button"
                        class={viewClass(view.mode)}
                        title={view.title}
                        aria-label={view.title}
                        onclick={() => onSelectViewMode(view.mode)}
                    >
                        <view.icon size={17} aria-hidden="true" />
                    </button>
                {/each}
            </div>
        {/if}
    </div>

    {#if loading}
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
            {#each Array(5) as _, idx (idx)}
                <div class="space-y-2">
                    <div
                        class="aspect-[2/3] w-full animate-pulse rounded-xl bg-[var(--color-panel-line)]"
                    ></div>
                    <div
                        class="h-3 w-3/4 animate-pulse rounded bg-[var(--color-panel-line)]"
                    ></div>
                </div>
            {/each}
        </div>
    {:else if error}
        <div class="flex flex-col items-start gap-2 rounded-xl bg-rose-400/5 p-4">
            <p class="text-sm text-rose-200" role="alert">{errorMessage(error)}</p>
            <button
                type="button"
                class="inline-flex items-center gap-2 rounded-md bg-accent px-3 py-1.5 text-xs font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                onclick={onRetry}
            >
                <RefreshCw size={14} aria-hidden="true" />
                {i18n.t.common.retry}
            </button>
        </div>
    {:else if related.length === 0}
        <p class="rounded-xl bg-[var(--color-panel-line)] p-5 text-sm text-muted">
            {i18n.t.detail.relatedEmpty}
        </p>
    {:else if viewMode === "grouped"}
        <div class="space-y-8">
            {#each groups as group (group.id)}
                <div class="space-y-3">
                    <div
                        class="flex items-center gap-2.5 border-b border-white/[0.08] pb-2.5"
                    >
                        <h3 class="text-base sm:text-lg font-bold text-white tracking-tight">
                            {group.title}
                        </h3>
                        <span
                            class="rounded-full bg-white/10 px-2.5 py-0.5 text-xs font-bold text-muted"
                        >
                            {group.items.length}
                        </span>
                    </div>
                    <div
                        class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5"
                    >
                        {#each group.items as rel (rel.id)}
                            {@render relatedCard(rel)}
                        {/each}
                    </div>
                </div>
            {/each}
        </div>
    {:else if viewMode === "timeline"}
        <div
            class="relative pl-6 sm:pl-8 space-y-4 before:absolute before:bottom-3 before:left-[11px] sm:before:left-[15px] before:top-3 before:w-0.5 before:bg-gradient-to-b before:from-accent before:via-accent/40 before:to-transparent"
        >
            {#each timeline as item (item.id)}
                {@render timelineRow(item)}
            {/each}
        </div>
    {:else}
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
            {#each related as rel (rel.id)}
                {@render relatedCard(rel)}
            {/each}
        </div>
    {/if}
</section>

{#snippet relatedCard(rel: RelatedEntry)}
    <button
        type="button"
        class="group relative flex flex-col aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/[0.06] bg-[var(--color-overlay-strong)] text-left transition duration-300 hover:border-accent/50 hover:shadow-xl hover:shadow-accent/10 cursor-pointer"
        onclick={() => onOpen(rel)}
    >
        {#if rel.coverUrl}
            <img
                src={rel.coverUrl}
                alt={rel.title}
                class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
                loading="lazy"
            />
        {:else}
            <div
                class="grid h-full w-full place-items-center bg-[var(--color-field)] text-muted"
            >
                <ImageIcon size={32} stroke-width={1.25} aria-hidden="true" />
            </div>
        {/if}

        {#if rel.localItem}
            <div class="absolute left-2.5 top-2.5 z-20 flex items-center">
                <div
                    class={`relative z-10 flex h-7 w-7 items-center justify-center rounded-full shadow-lg backdrop-blur ${relatedStatusClasses(rel.localItem.status)}`}
                    title={statusLabel(rel.localItem.status)}
                >
                    {#if rel.localItem.status === 0}
                        <Bookmark size={13} stroke-width={2.2} aria-hidden="true" />
                    {:else if rel.localItem.status === 1}
                        <Play
                            size={12}
                            fill="currentColor"
                            class="translate-x-0.5"
                            aria-hidden="true"
                        />
                    {:else if rel.localItem.status === 2}
                        <Check size={14} stroke-width={3} aria-hidden="true" />
                    {:else if rel.localItem.status === 3}
                        <Pause size={12} stroke-width={2.5} aria-hidden="true" />
                    {:else if rel.localItem.status === 4}
                        <X size={13} stroke-width={2.5} aria-hidden="true" />
                    {/if}
                </div>

                {#if rel.localItem.score !== null && rel.localItem.score > 0}
                    <div
                        class="relative z-20 -ml-2 flex h-7 w-7 items-center justify-center rounded-full bg-[var(--color-score-bg)] text-white shadow-lg border-2 border-[color-mix(in_oklab,var(--color-accent-line)_80%,transparent)] ring-2 ring-[color-mix(in_oklab,var(--color-accent-line)_30%,transparent)] font-black text-xs select-none"
                        title={`${i18n.t.createModal.fields.score}: ${rel.localItem.score}`}
                    >
                        {rel.localItem.score}
                    </div>
                {/if}
            </div>
        {/if}

        <div
            class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/95 via-black/85 to-transparent p-3 pt-12 flex flex-col justify-end pointer-events-none"
        >
            <span
                class="line-clamp-2 text-sm font-bold leading-snug text-white transition group-hover:text-accent-soft drop-shadow-md"
            >
                {rel.title}
            </span>
            <div class="mt-1.5 flex items-center justify-between gap-1 text-xs">
                {#if rel.relationType}
                    <span
                        class="rounded bg-accent/25 border border-accent/40 px-2 py-0.5 text-[11px] font-semibold text-accent-soft backdrop-blur-sm"
                    >
                        {rel.relationType}
                    </span>
                {:else}
                    <span class="text-[11px] text-slate-300"
                        >{formatMediaDisplayType(rel)}</span
                    >
                {/if}
                {#if rel.year}
                    <span class="font-medium text-slate-300 text-[11px]">
                        {rel.year}
                    </span>
                {/if}
            </div>
        </div>
    </button>
{/snippet}

{#snippet timelineRow(item: TimelineEntry)}
    <div class="relative flex items-center gap-4 group">
        <div
            class={`absolute -left-6 sm:-left-8 flex h-6 w-6 items-center justify-center rounded-full border-2 transition-transform duration-300 group-hover:scale-110 ${
                item.isCurrent
                    ? "border-accent bg-accent text-white shadow-lg shadow-accent/50 ring-4 ring-accent/20"
                    : item.localItem
                      ? "border-emerald-500 bg-[var(--color-field)] text-emerald-400"
                      : "border-white/[0.14] bg-[var(--color-field)] text-slate-400"
            }`}
        >
            {#if item.isCurrent}
                <div class="h-2 w-2 rounded-full bg-white"></div>
            {:else if item.localItem}
                <Check size={12} stroke-width={3} aria-hidden="true" />
            {:else}
                <div class="h-1.5 w-1.5 rounded-full bg-white/40"></div>
            {/if}
        </div>

        <button
            type="button"
            class={`flex flex-1 items-center gap-3.5 rounded-xl border p-2.5 transition text-left cursor-pointer ${
                item.isCurrent
                    ? "border-accent/60 bg-accent/10 shadow-md ring-1 ring-accent/30"
                    : "border-white/[0.06] bg-[var(--color-panel-line)] hover:border-white/[0.14] hover:bg-[var(--color-panel-raised)]"
            }`}
            onclick={() => {
                if (item.isCurrent || !item.rawItem) return;
                onOpen(item.rawItem);
            }}
        >
            <div
                class="relative aspect-[2/3] h-16 shrink-0 overflow-hidden rounded-lg bg-[var(--color-field)]"
            >
                {#if item.coverUrl}
                    <img
                        src={item.coverUrl}
                        alt={item.title}
                        class="h-full w-full object-cover"
                    />
                {:else}
                    <div class="grid h-full place-items-center text-muted">
                        <ImageIcon size={18} aria-hidden="true" />
                    </div>
                {/if}

                {#if item.localItem}
                    <div class="absolute left-1 top-1 flex items-center">
                        <div
                            class={`h-4 w-4 rounded-full flex items-center justify-center ${relatedStatusClasses(item.localItem.status)}`}
                        >
                            {#if item.localItem.status === 2}
                                <Check size={8} stroke-width={3} aria-hidden="true" />
                            {/if}
                        </div>
                    </div>
                {/if}
            </div>

            <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                    {#if item.year}
                        <span
                            class="rounded bg-white/10 px-1.5 py-0.5 text-[11px] font-bold text-accent-soft"
                        >
                            {item.year}
                        </span>
                    {/if}
                    <span
                        class={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                            item.isCurrent
                                ? "bg-accent text-white"
                                : "bg-white/5 text-slate-300 border border-white/[0.08]"
                        }`}
                    >
                        {item.relationType}
                    </span>
                    <span class="text-[11px] text-muted">{item.formatDisplay}</span>
                </div>

                <h3
                    class={`mt-1 truncate text-sm font-bold ${item.isCurrent ? "text-accent-soft" : "text-white group-hover:text-accent-soft"}`}
                >
                    {item.title}
                </h3>
            </div>

            <div class="shrink-0 pr-2">
                {#if item.localItem?.score}
                    <span
                        class="rounded-full bg-[var(--color-score-bg)] border border-[color-mix(in_oklab,var(--color-accent-line)_80%,transparent)] px-2.5 py-0.5 text-xs font-black text-white"
                    >
                        {item.localItem.score}
                    </span>
                {:else if !item.localItem && !item.isCurrent}
                    <span
                        class="rounded-md border border-white/[0.08] bg-white/5 px-2.5 py-1 text-xs font-medium text-slate-300 group-hover:border-accent/40 group-hover:text-accent-soft"
                    >
                        {i18n.t.detail.overviewBadge}
                    </span>
                {/if}
            </div>
        </button>
    </div>
{/snippet}
