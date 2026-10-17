<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats } from "$shared/types";

    interface Props {
        stats: AdvancedStats;
    }

    let { stats }: Props = $props();

    function formatNumber(value: number): string {
        return new Intl.NumberFormat(i18n.current).format(value);
    }

    interface CategorySlice {
        id: string;
        label: string;
        hours: number;
        color: string;
        extraText?: string;
    }

    const categories = $derived.by<CategorySlice[]>(() => [
        {
            id: "game",
            label: i18n.t.stats.games,
            hours: stats.gameHours,
            color: "#6366f1",
        },
        {
            id: "series",
            label: i18n.t.stats.series,
            hours: stats.seriesHours,
            color: "#06b6d4",
            extraText: `${formatNumber(stats.totalEpisodesWatched)} ${i18n.t.stats.episodesShort}`,
        },
        {
            id: "movie",
            label: i18n.t.stats.movies,
            hours: stats.movieHours,
            color: "#3b82f6",
        },
        {
            id: "anime",
            label: i18n.t.stats.anime,
            hours: stats.animeHours,
            color: "#a855f7",
            extraText: `${formatNumber(stats.totalEpisodesWatched)} ${i18n.t.stats.episodesShort}`,
        },
        {
            id: "book",
            label: i18n.t.stats.books,
            hours: stats.bookHours,
            color: "#f59e0b",
            extraText: `${formatNumber(stats.totalPagesRead)} ${i18n.t.stats.pagesShort}`,
        },
        {
            id: "manga",
            label: i18n.t.stats.manga,
            hours: stats.mangaHours,
            color: "#10b981",
            extraText: `${formatNumber(stats.totalChaptersRead)} ${i18n.t.stats.chaptersShort}`,
        },
    ]);

    const totalCalculatedHours = $derived(
        categories.reduce((acc, cat) => acc + cat.hours, 0)
    );

    const radius = 70;
    const strokeWidth = 20;
    const circumference = 2 * Math.PI * radius;

    interface DonutSegment {
        id: string;
        dashArray: string;
        dashOffset: number;
        color: string;
        percentage: number;
    }

    const segments = $derived.by<DonutSegment[]>(() => {
        if (totalCalculatedHours <= 0) return [];

        let currentOffset = 0;
        return categories
            .filter((c) => c.hours > 0)
            .map((c) => {
                const ratio = c.hours / totalCalculatedHours;
                const arcLength = ratio * circumference;
                const segment: DonutSegment = {
                    id: c.id,
                    dashArray: `${arcLength} ${circumference - arcLength}`,
                    dashOffset: -currentOffset,
                    color: c.color,
                    percentage: Math.round(ratio * 100),
                };
                currentOffset += arcLength;
                return segment;
            });
    });
</script>

<div class="flex flex-col sm:flex-row items-center justify-center gap-6 my-auto w-full">
    <div class="relative flex h-48 w-48 shrink-0 items-center justify-center">
        <svg
            viewBox="0 0 180 180"
            class="h-full w-full -rotate-90 transform overflow-visible"
            aria-hidden="true"
        >
            {#if segments.length === 0}
                <circle
                    cx="90"
                    cy="90"
                    r={radius}
                    fill="transparent"
                    stroke="currentColor"
                    stroke-width="10"
                    class="text-white/10"
                />
            {:else}
                {#each segments as segment (segment.id)}
                    <circle
                        cx="90"
                        cy="90"
                        r={radius}
                        fill="transparent"
                        stroke={segment.color}
                        stroke-width={strokeWidth}
                        stroke-dasharray={segment.dashArray}
                        stroke-dashoffset={segment.dashOffset}
                        stroke-linecap="butt"
                    />
                {/each}
            {/if}
        </svg>

        <div class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center text-center">
            <span class="text-2xl font-black tabular-nums tracking-tight text-ink">
                {formatNumber(stats.totalHours)} {i18n.t.stats.hoursShort}
            </span>
            <span class="text-xs font-medium text-muted">
                {i18n.t.stats.totalTime}
            </span>
        </div>
    </div>

    <div class="grid w-full grid-cols-1 gap-2.5 sm:grid-cols-2">
        {#each categories as category (category.id)}
            {@const pct = totalCalculatedHours > 0 ? Math.round((category.hours / totalCalculatedHours) * 100) : 0}
            <div class="flex items-center justify-between rounded-lg bg-white/[0.02] p-2 px-3 border border-white/[0.03]">
                <div class="flex items-center gap-2.5 min-w-0">
                    <span
                        class="h-2.5 w-2.5 shrink-0 rounded-full"
                        style="background-color: {category.color};"
                    ></span>
                    <div class="min-w-0">
                        <p class="truncate text-xs font-medium text-ink">
                            {category.label}
                        </p>
                        {#if category.extraText}
                            <p class="truncate text-[11px] text-muted">
                                {category.extraText}
                            </p>
                        {/if}
                    </div>
                </div>

                <div class="text-right shrink-0 pl-2">
                    <p class="text-xs font-semibold tabular-nums text-ink">
                        {formatNumber(category.hours)} {i18n.t.stats.hoursShort}
                    </p>
                    <p class="text-[11px] tabular-nums text-muted">
                        {pct}%
                    </p>
                </div>
            </div>
        {/each}
    </div>
</div>
