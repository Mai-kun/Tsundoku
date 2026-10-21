<script lang="ts">
    import { Hourglass } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { SunkCost } from "$shared/types";

    interface Props {
        sunkCost: SunkCost;
    }

    let { sunkCost }: Props = $props();

    const PALETTE: Record<string, string> = {
        game: "#f43f5e",
        movie: "#fb923c",
        series: "#f59e0b",
        anime: "#eab308",
        book: "#a3e635",
        manga: "#84cc16",
    };

    const breakdown = $derived(
        Object.entries(sunkCost.categoryBreakdown)
            .filter(([, hours]) => hours > 0)
            .sort((a, b) => b[1] - a[1])
    );
    const breakdownSum = $derived(breakdown.reduce((sum, [, hours]) => sum + hours, 0));

    function categoryLabel(type: string): string {
        const labels = i18n.t.stats.genreCategories as Record<string, string>;
        return type in labels ? labels[type] : i18n.t.stats.taste.sunkCostOther;
    }
</script>

<div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
    <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
        <div class="flex items-center gap-2">
            <Hourglass class="size-4 text-rose-400" aria-hidden="true" />
            <h3 class="text-base font-semibold tracking-tight text-white">{i18n.t.stats.taste.sunkCostTitle}</h3>
        </div>
        <span class="rounded-full border border-rose-500/20 bg-rose-500/10 px-2.5 py-0.5 text-xs font-bold text-rose-300 tabular-nums">
            {sunkCost.percentageOfTotal}%
        </span>
    </div>

    <p class="text-sm leading-relaxed text-slate-300">
        {i18n.t.stats.taste.sunkCostMessage(Math.round(sunkCost.lowScoreHours).toString(), sunkCost.percentageOfTotal.toFixed(1).replace(/\.0$/, ""))}
    </p>

    <div class="mt-3 flex items-center gap-2 text-xs text-slate-400">
        <span class="rounded bg-white/5 px-2 py-0.5 tabular-nums">{i18n.t.stats.taste.sunkCostTitlesCount(sunkCost.titlesCount)}</span>
    </div>

    {#if breakdown.length > 0}
        <div class="mt-4 h-3 w-full rounded-full overflow-hidden bg-white/5 flex" role="img" aria-label={i18n.t.stats.taste.sunkCostTitle}>
            {#each breakdown as [type, hours] (type)}
                <div
                    class="h-full transition-[width] duration-300"
                    style="width: {(hours / breakdownSum) * 100}%; background-color: {PALETTE[type] ?? '#f43f5e'};"
                    title="{categoryLabel(type)}: {Math.round(hours)} {i18n.t.stats.hoursShort}"
                ></div>
            {/each}
        </div>
        <div class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-400">
            {#each breakdown as [type, hours] (type)}
                <span class="flex items-center gap-1.5">
                    <span class="size-2 rounded-full" style="background-color: {PALETTE[type] ?? '#f43f5e'};"></span>
                    {categoryLabel(type)}
                    <span class="tabular-nums text-slate-500">{Math.round(hours)} {i18n.t.stats.hoursShort}</span>
                </span>
            {/each}
        </div>
    {/if}

    <p class="mt-4 border-l-2 border-emerald-500/40 pl-3 text-sm leading-relaxed text-emerald-300/90">
        {i18n.t.stats.taste.sunkCostAdvice}
    </p>
</div>
