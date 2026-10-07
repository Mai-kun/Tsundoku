<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";

    interface Props {
        dailyActivity: Record<string, number>;
    }

    let { dailyActivity = {} }: Props = $props();

    const cells = $derived.by(() => {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const days = Array.from({ length: 365 }, (_, index) => {
            const date = new Date(today);
            date.setDate(today.getDate() - (364 - index));
            const iso = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
            return { date, iso, count: dailyActivity[iso] ?? 0 };
        });
        const mondayOffset = (days[0].date.getDay() + 6) % 7;
        return [...Array.from({ length: mondayOffset }, () => null), ...days];
    });

    const totalActivity = $derived(Object.values(dailyActivity).reduce((sum, count) => sum + count, 0));

    function intensity(count: number): string {
        if (count === 0) return "bg-white/[0.04]";
        if (count <= 2) return "bg-[#5844e0]/35";
        if (count <= 5) return "bg-[#5844e0]/65";
        if (count <= 9) return "bg-[#5844e0]";
        return "bg-[#818cf8]";
    }

    function formatDate(date: Date): string {
        return new Intl.DateTimeFormat(i18n.current, { day: "numeric", month: "short", year: "numeric" }).format(date);
    }
</script>

<section class="bg-[#151a26] border border-white/5 rounded-xl p-5">
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <h3 class="text-base font-semibold tracking-tight text-white">{i18n.t.stats.heatmapTitle}</h3>
        <span class="text-xs font-semibold text-[#a5b4fc]">{i18n.t.stats.heatmapTotal(totalActivity)}</span>
    </div>

    <div class="overflow-x-auto pb-2">
        <div class="grid min-w-[760px] grid-rows-7 grid-flow-col grid-cols-[repeat(53,minmax(0,1fr))] gap-1" aria-label={i18n.t.stats.heatmapTitle}>
            {#each cells as cell, index (cell?.iso ?? `empty-${index}`)}
                {#if cell}
                    <div
                        class="aspect-square rounded-[2px] {intensity(cell.count)} transition-colors duration-200 hover:ring-1 hover:ring-white/60"
                        title={i18n.t.stats.heatmapTooltip(formatDate(cell.date), cell.count)}
                        aria-label={i18n.t.stats.heatmapTooltip(formatDate(cell.date), cell.count)}
                    ></div>
                {:else}
                    <div class="aspect-square" aria-hidden="true"></div>
                {/if}
            {/each}
        </div>
    </div>

    <div class="mt-2 flex flex-wrap items-center justify-between gap-3 text-xs text-slate-400">
        <span>{i18n.t.stats.heatmapTotal(totalActivity)}</span>
        <div class="flex items-center gap-1.5" aria-label={`${i18n.t.stats.less} — ${i18n.t.stats.more}`}>
            <span>{i18n.t.stats.less}</span>
            <span class="size-3 rounded-[2px] bg-white/[0.04]"></span>
            <span class="size-3 rounded-[2px] bg-[#5844e0]/35"></span>
            <span class="size-3 rounded-[2px] bg-[#5844e0]/65"></span>
            <span class="size-3 rounded-[2px] bg-[#5844e0]"></span>
            <span class="size-3 rounded-[2px] bg-[#818cf8]"></span>
            <span>{i18n.t.stats.more}</span>
        </div>
    </div>
</section>
