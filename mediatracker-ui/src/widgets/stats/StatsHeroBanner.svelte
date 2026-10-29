<script lang="ts">
  import { Flame, Star, CheckCircle2 } from "$shared/ui/Icons";
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

<section class="space-y-4" data-widget="stats-hero">
  <div>
    <h1 class="text-ink text-2xl font-extrabold tracking-tight sm:text-3xl">
      {i18n.t.stats.heroTitle(formatNumber(stats.totalHours), formatNumber(stats.totalTitles))}
    </h1>
    <p class="text-muted mt-1 max-w-2xl text-sm sm:text-base">
      {i18n.t.stats.heroSubtitle(formatNumber(stats.totalDays))}
    </p>
  </div>

  <div class="grid grid-cols-1 gap-3.5 sm:grid-cols-3">
    <article
      class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10"
    >
      <div
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-amber-500/10 text-amber-500"
      >
        <Flame size={22} aria-hidden="true" />
      </div>
      <div class="min-w-0">
        <p class="text-muted text-xs font-medium">{i18n.t.stats.activityStreak}</p>
        <p class="text-ink mt-0.5 truncate text-base font-bold">
          {i18n.t.stats.streakDays(stats.currentStreakDays)}
        </p>
      </div>
    </article>

    <article
      class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10"
    >
      <div
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-yellow-500/10 text-yellow-400"
      >
        <Star size={22} class="fill-yellow-400/20" aria-hidden="true" />
      </div>
      <div class="min-w-0">
        <p class="text-muted text-xs font-medium">{i18n.t.stats.averageScore}</p>
        <p class="text-ink mt-0.5 truncate text-base font-bold">
          {stats.averageScore > 0 ? stats.averageScore : "—"} / 10
        </p>
      </div>
    </article>

    <article
      class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#151a26] p-4 transition-colors hover:border-white/10"
    >
      <div
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-emerald-500/10 text-emerald-400"
      >
        <CheckCircle2 size={22} aria-hidden="true" />
      </div>
      <div class="min-w-0">
        <p class="text-muted text-xs font-medium">{i18n.t.stats.completed}</p>
        <p class="text-ink mt-0.5 truncate text-base font-bold">
          {stats.completedTitles} / {stats.totalTitles} ({stats.completionRatePercent}%)
        </p>
      </div>
    </article>
  </div>
</section>
