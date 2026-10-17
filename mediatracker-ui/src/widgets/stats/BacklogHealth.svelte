<script lang="ts">
    import { Scale } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats } from "$shared/types";

    interface Props {
        stats: AdvancedStats;
    }

    let { stats }: Props = $props();

    const totalTitles = $derived(stats.totalTitles);
    const completedTitles = $derived(stats.completedTitles);

    const rawPlanned = $derived(
        (stats as { plannedTitles?: number }).plannedTitles
    );

    const plannedCount = $derived(
        rawPlanned !== undefined
            ? Math.max(0, rawPlanned)
            : Math.max(0, totalTitles - completedTitles)
    );

    const inProgressCount = $derived(
        rawPlanned !== undefined
            ? Math.max(0, totalTitles - completedTitles - plannedCount)
            : 0
    );

    const completedPercent = $derived(
        totalTitles > 0 ? (completedTitles / totalTitles) * 100 : 0
    );

    const plannedPercent = $derived(
        totalTitles > 0 ? (plannedCount / totalTitles) * 100 : 0
    );

    const inProgressPercent = $derived(
        totalTitles > 0 ? (inProgressCount / totalTitles) * 100 : 0
    );

    const verdictText = $derived.by(() => {
        if (stats.totalTitles === 0) {
            return i18n.t.stats.emptyVerdict;
        }
        if (stats.completionRatePercent >= 60) {
            return i18n.t.stats.productiveVerdict;
        }
        if (stats.completionRatePercent >= 30) {
            return i18n.t.stats.balancedVerdict;
        }
        return i18n.t.stats.tsundokuVerdict;
    });
</script>

<section class="bg-[#151a26] border border-white/5 rounded-xl p-5 mt-6">
    <div class="flex items-center gap-2 mb-4">
        <Scale class="size-4 text-emerald-400" aria-hidden="true" />
        <h3 class="text-base font-semibold tracking-tight text-white">
            {i18n.t.stats.backlogTitle}
        </h3>
    </div>

    <div class="h-3 rounded-full overflow-hidden flex w-full bg-white/5">
        {#if totalTitles === 0}
            <div class="h-full w-full bg-white/10"></div>
        {:else}
            {#if completedPercent > 0}
                <div
                    class="h-full bg-[#10b981] first:rounded-l-full last:rounded-r-full"
                    style="width: {completedPercent}%;"
                    title={i18n.t.stats.segmentTooltip(i18n.t.stats.completed, completedTitles, Math.round(completedPercent))}
                ></div>
            {/if}
            {#if inProgressPercent > 0}
                <div
                    class="h-full bg-[#8b5cf6] first:rounded-l-full last:rounded-r-full"
                    style="width: {inProgressPercent}%;"
                    title={i18n.t.stats.segmentTooltip(i18n.t.stats.inProgress, inProgressCount, Math.round(inProgressPercent))}
                ></div>
            {/if}
            {#if plannedPercent > 0}
                <div
                    class="h-full bg-[#3b82f6] first:rounded-l-full last:rounded-r-full"
                    style="width: {plannedPercent}%;"
                    title={i18n.t.stats.segmentTooltip(i18n.t.stats.planned, plannedCount, Math.round(plannedPercent))}
                ></div>
            {/if}
        {/if}
    </div>

    <div class="flex flex-wrap items-center gap-4 sm:gap-6 mt-3.5 text-xs">
        <div class="flex items-center gap-2">
            <span class="size-2.5 rounded-full shrink-0 bg-[#10b981]"></span>
            <span class="text-slate-300">
                {i18n.t.stats.completed}: <span class="font-semibold text-white tabular-nums">{completedTitles}</span>
            </span>
        </div>
        <div class="flex items-center gap-2">
            <span class="size-2.5 rounded-full shrink-0 bg-[#8b5cf6]"></span>
            <span class="text-slate-300">
                {i18n.t.stats.inProgress}: <span class="font-semibold text-white tabular-nums">{inProgressCount}</span>
            </span>
        </div>
        <div class="flex items-center gap-2">
            <span class="size-2.5 rounded-full shrink-0 bg-[#3b82f6]"></span>
            <span class="text-slate-300">
                {i18n.t.stats.planned}: <span class="font-semibold text-white tabular-nums">{plannedCount}</span>
            </span>
        </div>
    </div>

    <div class="bg-white/[0.02] border border-white/5 rounded-lg p-3.5 mt-4 text-sm text-slate-300 leading-relaxed">
        {verdictText}
    </div>
</section>
