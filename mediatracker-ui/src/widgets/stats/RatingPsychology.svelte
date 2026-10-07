<script lang="ts">
    import type { AdvancedStats } from "$shared/types";

    interface Props {
        stats: AdvancedStats;
    }

    let { stats }: Props = $props();

    const scores = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

    const distribution = $derived.by(() => {
        return scores.map((score) => ({
            score,
            count: stats.scoreDistribution?.[score] ?? 0,
        }));
    });

    const maxCount = $derived(
        Math.max(1, ...distribution.map((d) => d.count))
    );

    const typeLabels: Record<string, string> = {
        game: "Игры",
        movie: "Фильмы",
        series: "Сериалы",
        anime: "Аниме",
        book: "Книги",
        manga: "Манга",
    };

    const typeScores = $derived.by(() => {
        if (!stats.averageScoreByType) return [];
        return Object.entries(stats.averageScoreByType)
            .filter(([_, score]) => score > 0)
            .map(([typeKey, score]) => ({
                label: typeLabels[typeKey] ?? typeKey,
                score,
            }));
    });
</script>

<div class="space-y-4">
    <div class="flex items-center justify-between">
        <h3 class="text-base font-semibold tracking-tight text-ink">
            Психология оценок
        </h3>
        {#if stats.averageScore > 0}
            <span class="text-xs font-medium text-amber-400/90">
                Средняя: {stats.averageScore} ★
            </span>
        {/if}
    </div>

    <div class="space-y-1.5" role="list" aria-label="Распределение оценок">
        {#each distribution as { score, count } (score)}
            {@const pct = (count / maxCount) * 100}
            <div class="flex items-center gap-2.5 text-xs">
                <span class="w-8 shrink-0 text-right font-semibold text-amber-400">
                    {score} ★
                </span>

                <div class="relative h-3 flex-1 overflow-hidden rounded-full bg-white/[0.04]">
                    <div
                        class="h-full w-full origin-left rounded-full bg-gradient-to-r from-amber-500/70 to-amber-400 transition-transform duration-500 ease-out"
                        style="transform: scaleX({pct / 100});"
                    ></div>
                </div>

                <span class="w-7 shrink-0 text-right font-medium tabular-nums text-muted">
                    {count}
                </span>
            </div>
        {/each}
    </div>

    {#if typeScores.length > 0}
        <div class="pt-2 border-t border-white/[0.04]">
            <p class="text-[11px] font-medium text-muted uppercase tracking-wider mb-2">
                Средний балл по категориям
            </p>
            <div class="flex flex-wrap gap-2">
                {#each typeScores as item (item.label)}
                    <span class="inline-flex items-center gap-1.5 rounded-md border border-amber-500/15 bg-amber-500/5 px-2.5 py-1 text-xs font-medium text-amber-300">
                        <span>{item.label}:</span>
                        <span class="font-bold">{item.score} ★</span>
                    </span>
                {/each}
            </div>
        </div>
    {/if}
</div>
