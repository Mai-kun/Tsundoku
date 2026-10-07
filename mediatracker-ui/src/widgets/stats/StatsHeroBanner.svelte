<script lang="ts">
    import { Flame, Star, CheckCircle2 } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import type { AdvancedStats } from "$shared/types";

    interface Props {
        stats: AdvancedStats;
    }

    let { stats }: Props = $props();

    function formatNumber(value: number): string {
        return new Intl.NumberFormat(i18n.current).format(value);
    }
</script>

<section class="space-y-4">
    <div>
        <h1 class="text-2xl sm:text-3xl font-extrabold tracking-tight text-ink">
            Вы провели {formatNumber(stats.totalHours)} ч. за {formatNumber(stats.totalTitles)} тайтлами.
        </h1>
        <p class="mt-1 text-sm sm:text-base text-muted">
            Это {formatNumber(stats.totalDays)} дн. непрерывных историй, миров и приключений.
        </p>
    </div>

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
        <article class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10">
            <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-amber-500/10 text-amber-500">
                <Flame size={22} aria-hidden="true" />
            </div>
            <div class="min-w-0">
                <p class="text-xs font-medium text-muted">Стрик активности</p>
                <p class="mt-0.5 truncate text-base font-bold text-ink">
                    {stats.currentStreakDays} дн. активности подряд
                </p>
            </div>
        </article>

        <article class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10">
            <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-yellow-500/10 text-yellow-400">
                <Star size={22} class="fill-yellow-400/20" aria-hidden="true" />
            </div>
            <div class="min-w-0">
                <p class="text-xs font-medium text-muted">Средний балл</p>
                <p class="mt-0.5 truncate text-base font-bold text-ink">
                    {stats.averageScore > 0 ? stats.averageScore : "—"} / 10
                </p>
            </div>
        </article>

        <article class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10">
            <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-emerald-500/10 text-emerald-400">
                <CheckCircle2 size={22} aria-hidden="true" />
            </div>
            <div class="min-w-0">
                <p class="text-xs font-medium text-muted">Завершено</p>
                <p class="mt-0.5 truncate text-base font-bold text-ink">
                    {stats.completedTitles} / {stats.totalTitles} ({stats.completionRatePercent}%)
                </p>
            </div>
        </article>
    </div>
</section>
