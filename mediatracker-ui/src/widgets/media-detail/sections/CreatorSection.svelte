<script lang="ts">
    import { getCreatorSummary } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { CreatorRole, MediaItem } from "$shared/types";
    import { BookOpen, Clapperboard, Search, Star, User } from "$shared/ui/Icons.svelte";

    interface Props {
        creatorName: string;
        role: CreatorRole;
        /** Overrides the role's default caption (network, mangaka, developer). */
        label?: string | null;
        currentMediaId: string;
        imageUrl?: string | null;
        onOpenMedia: (item: MediaItem) => void;
        onSearch: (query: string) => void;
    }

    let {
        creatorName,
        role,
        label = null,
        currentMediaId,
        imageUrl = null,
        onOpenMedia,
        onSearch,
    }: Props = $props();
    let summary = $state<Awaited<ReturnType<typeof getCreatorSummary>>>(null);
    let loading = $state(true);

    $effect(() => {
        const name = creatorName;
        const currentId = currentMediaId;
        const currentRole = role;
        let active = true;
        loading = true;
        void getCreatorSummary(name, currentRole, currentId)
            .then((value) => {
                if (active) summary = value;
            })
            .catch(() => {
                if (active) summary = null;
            })
            .finally(() => {
                if (active) loading = false;
            });
        return () => { active = false; };
    });

    const completionPercent = $derived(
        summary && summary.totalCount > 0
            ? Math.round((summary.completedCount / summary.totalCount) * 100)
            : 0,
    );

    function statusLabel(status: MediaItem["status"]): string {
        switch (status) {
            case 0: return i18n.t.status.planned;
            case 1: return i18n.t.status.inProgress;
            case 2: return i18n.t.status.completed;
            case 3: return i18n.t.status.paused;
            default: return i18n.t.status.dropped;
        }
    }
</script>

<section class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
    <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex min-w-0 items-center gap-3">
            {#if imageUrl}
                <img
                    src={imageUrl}
                    alt={creatorName}
                    loading="lazy"
                    referrerpolicy="no-referrer"
                    class="h-11 w-11 shrink-0 rounded-xl bg-white/[0.06] object-cover"
                />
            {:else}
                <span class="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-white/[0.06] text-accent-soft">
                    {#if role === "director"}<Clapperboard size={21} />
                    {:else if role === "author"}<BookOpen size={21} />
                    {:else}<User size={21} />{/if}
                </span>
            {/if}
            <div class="min-w-0">
                <p class="text-xs font-semibold uppercase tracking-[0.16em] text-muted">{label ?? i18n.t.creator[role]}</p>
                <h2 class="truncate text-xl font-bold text-ink">{creatorName}</h2>
            </div>
        </div>
        {#if summary}
            <div class="flex flex-wrap gap-2">
                <div class="rounded-lg border border-white/[0.06] bg-black/10 px-3 py-2 text-sm text-muted">
                    {i18n.t.creator.completedOf(summary.completedCount, summary.totalCount)}
                    <span class="ml-1 text-ink">({completionPercent}%)</span>
                </div>
                {#if summary.averageScore !== null}
                    <div class="flex items-center gap-1.5 rounded-lg border border-white/[0.06] bg-black/10 px-3 py-2 text-sm text-muted">
                        {i18n.t.creator.averageScore}: <span class="font-semibold text-ink">{summary.averageScore.toFixed(1)}</span>
                        <Star size={14} class="fill-amber-400 text-amber-400" />
                    </div>
                {/if}
            </div>
        {/if}
    </div>

    {#if loading}
        <p class="text-sm text-muted">{i18n.t.creator.loading}</p>
    {:else if summary}
        <p class="text-sm text-muted">
            {i18n.t.creator.inLibrary}: <span class="font-semibold text-ink">{i18n.t.creator.titlesCount(summary.totalCount)}</span>
        </p>

        {#if summary.otherItems.length > 0}
            <div class="space-y-2">
                <h3 class="text-sm font-semibold text-ink">{i18n.t.creator.otherWorks}</h3>
                <div class="flex gap-3 overflow-x-auto pb-2">
                    {#each summary.otherItems as item (item.id)}
                        <button
                            type="button"
                            class="group w-24 shrink-0 text-left sm:w-28"
                            onclick={() => onOpenMedia(item)}
                            aria-label={`${item.title}, ${statusLabel(item.status)}`}
                        >
                            <div class="relative aspect-[2/3] overflow-hidden rounded-lg bg-black/20">
                                {#if item.coverUrl}
                                    <img src={item.coverUrl} alt="" loading="lazy" referrerpolicy="no-referrer" class="h-full w-full object-cover transition group-hover:scale-[1.03]" />
                                {:else}
                                    <div class="grid h-full place-items-center px-2 text-center text-xs text-muted">{item.title}</div>
                                {/if}
                            </div>
                            <span class="mt-1.5 block truncate text-xs font-medium text-ink group-hover:text-accent-soft">{item.title}</span>
                            <span class="flex items-center justify-between gap-1 text-[11px] text-muted">
                                <span class="truncate">{statusLabel(item.status)}</span>
                                {#if item.score !== null}<span class="shrink-0 text-amber-300">★ {item.score}</span>{/if}
                            </span>
                        </button>
                    {/each}
                </div>
            </div>
        {:else}
            <p class="text-sm text-muted">{i18n.t.creator.noOtherItems}</p>
        {/if}
    {/if}

    <button
        type="button"
        class="inline-flex items-center gap-2 rounded-lg border border-white/[0.08] bg-white/[0.04] px-3 py-2 text-sm font-medium text-ink transition hover:bg-white/[0.08]"
        onclick={() => onSearch(creatorName)}
    ><Search size={15} />{i18n.t.creator.searchMore} {creatorName}</button>
</section>
