<script lang="ts">
    import { CalendarDays } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";

    interface MonthlyCompletionItem {
        monthYear: string;
        count: number;
    }

    interface Props {
        completions: MonthlyCompletionItem[];
    }

    let { completions = [] }: Props = $props();

    const totalCompletions = $derived(
        completions.reduce((acc, curr) => acc + curr.count, 0)
    );

    const maxCount = $derived(
        Math.max(...completions.map((c) => c.count), 1)
    );

    function formatMonth(monthYear: string): string {
        const date = new Date(`${monthYear}-01T00:00:00`);
        return Number.isNaN(date.getTime()) ? monthYear : new Intl.DateTimeFormat(i18n.current, { month: "short" }).format(date);
    }

    function formatTooltip(monthYear: string, count: number): string {
        const date = new Date(`${monthYear}-01T00:00:00`);
        const formattedDate = Number.isNaN(date.getTime()) ? monthYear : new Intl.DateTimeFormat(i18n.current, { month: "short", year: "numeric" }).format(date);
        return `${formattedDate}: ${i18n.t.stats.completedTooltip(count)}`;
    }
</script>

<div class="bg-[#151a26] border border-white/5 rounded-xl p-5">
    <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
            <CalendarDays class="size-4 text-[#818cf8]" aria-hidden="true" />
            <h3 class="text-base font-semibold tracking-tight text-white">
                {i18n.t.stats.monthlyActivity}
            </h3>
        </div>
        <span class="inline-flex items-center rounded-md bg-[#5844e0]/15 border border-[#5844e0]/30 px-2.5 py-1 text-xs font-semibold text-[#818cf8]">
            {i18n.t.stats.completedInYear(totalCompletions)}
        </span>
    </div>

    <div class="h-44 flex items-end justify-between gap-2 pt-6 pb-2">
        {#each completions as c (c.monthYear)}
            {@const heightPercent = (c.count / maxCount) * 100}
            <div class="flex-1 h-full flex flex-col items-center justify-end group relative cursor-pointer">
                <!-- Tooltip -->
                <div class="pointer-events-none absolute bottom-full mb-8 z-20 hidden group-hover:flex flex-col items-center whitespace-nowrap">
                    <div class="rounded-lg bg-slate-900 border border-white/10 px-2.5 py-1 text-xs font-medium text-slate-200 shadow-xl">
                        {formatTooltip(c.monthYear, c.count)}
                    </div>
                    <div class="size-1.5 rotate-45 bg-slate-900 border-r border-b border-white/10 -mt-1"></div>
                </div>

                {#if c.count > 0}
                    <span class="text-[11px] font-semibold text-slate-300 mb-1 tabular-nums">
                        {c.count}
                    </span>
                    <div class="w-full flex-1 flex items-end">
                        <div
                            class="h-full w-full origin-bottom rounded-t-md bg-gradient-to-t from-[#5844e0] to-[#818cf8] hover:brightness-125"
                            style="transform: scaleY({heightPercent / 100});"
                        ></div>
                    </div>
                {:else}
                    <div
                        class="w-full bg-white/5 rounded-t-sm h-[4px] min-h-[4px]"
                    ></div>
                {/if}
            </div>
        {/each}
    </div>

    <div class="flex items-center justify-between gap-2 border-t border-white/5 pt-2">
        {#each completions as c (c.monthYear)}
            <span class="flex-1 text-center text-xs text-slate-400 font-medium">
                {formatMonth(c.monthYear)}
            </span>
        {/each}
    </div>
</div>
