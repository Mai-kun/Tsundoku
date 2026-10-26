<script lang="ts">
  import { Ban } from "$shared/ui/Icons.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { DropAnalytics } from "$shared/types";
  import { getDropReasonLabel } from "$entities/media/model/dropReasons";

  interface Props {
    analytics: DropAnalytics;
  }

  let { analytics }: Props = $props();

  const isRu = $derived(i18n.current === "ru");

  const earlyShare = $derived(
    analytics.totalDropped > 0
      ? Math.round((analytics.earlyDropCount / analytics.totalDropped) * 100)
      : 0,
  );
  const midShare = $derived(
    analytics.totalDropped > 0
      ? Math.round((analytics.midDropCount / analytics.totalDropped) * 100)
      : 0,
  );
  const lateShare = $derived(
    analytics.totalDropped > 0 ? Math.max(0, 100 - earlyShare - midShare) : 0,
  );

  const insightText = $derived.by(() => {
    if (analytics.totalDropped === 0) return "";
    if (analytics.earlyDropCount >= analytics.totalDropped * 0.5) {
      return isRu
        ? "Вы не боитесь бросать скучное в самом начале — это экономит сотни часов жизни для действительно любимых историй."
        : "You aren't afraid to drop boring titles early — saving hundreds of hours of life for stories you truly love.";
    }
    if (analytics.lateDropCount >= analytics.totalDropped * 0.4) {
      return isRu
        ? "Вы даете произведениям шанс раскрыться до самого конца. Помните: дропать никогда не поздно, если история перестала приносить удовольствие."
        : "You give stories a chance to unfold until the very end. Remember: it's never too late to drop something that stopped bringing joy.";
    }
    return isRu
      ? "Вы тонко чувствуете момент, когда история перестает радовать, и освобождаете место для новых открытий."
      : "You have a keen sense of when a story stops resonating, freeing up time for new discoveries.";
  });
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <!-- Header -->
  <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <Ban class="size-4 text-rose-400" aria-hidden="true" />
      <h3 class="text-base font-semibold tracking-tight text-white">
        {i18n.t.stats.taste.dropAnalytics.title}
      </h3>
    </div>
    <span
      class="rounded-full border border-rose-500/20 bg-rose-500/10 px-2.5 py-0.5 text-xs font-bold text-rose-300 tabular-nums"
    >
      {i18n.t.stats.taste.dropAnalytics.totalDropped(analytics.totalDropped)}
    </span>
  </div>

  {#if analytics.totalDropped === 0}
    <p class="text-muted flex min-h-24 items-center justify-center text-center text-xs">
      {i18n.t.stats.taste.dropAnalytics.empty}
    </p>
  {:else}
    <!-- Point of No Return -->
    <div class="space-y-2.5">
      <div class="flex items-center justify-between">
        <span class="text-xs font-semibold tracking-wider text-slate-400 uppercase">
          {i18n.t.stats.taste.dropAnalytics.noReturnTitle}
        </span>
        <span class="text-xs font-bold text-slate-200 tabular-nums">
          avg {analytics.averageDropProgressPercent}%
        </span>
      </div>

      <p class="text-sm leading-relaxed text-slate-300">
        {i18n.t.stats.taste.dropAnalytics.avgDropText(analytics.averageDropProgressPercent)}
      </p>

      <!-- 3-color progress bar -->
      <div
        class="flex h-3 w-full overflow-hidden rounded-full bg-white/5"
        role="img"
        aria-label={i18n.t.stats.taste.dropAnalytics.noReturnTitle}
      >
        {#if earlyShare > 0}
          <div
            class="h-full bg-emerald-400 transition-[width] duration-300"
            style="width: {earlyShare}%;"
            title="{i18n.t.stats.taste.dropAnalytics
              .earlyDrop}: {analytics.earlyDropCount} ({earlyShare}%)"
          ></div>
        {/if}
        {#if midShare > 0}
          <div
            class="h-full bg-amber-400 transition-[width] duration-300"
            style="width: {midShare}%;"
            title="{i18n.t.stats.taste.dropAnalytics
              .midDrop}: {analytics.midDropCount} ({midShare}%)"
          ></div>
        {/if}
        {#if lateShare > 0}
          <div
            class="h-full bg-rose-400 transition-[width] duration-300"
            style="width: {lateShare}%;"
            title="{i18n.t.stats.taste.dropAnalytics
              .lateDrop}: {analytics.lateDropCount} ({lateShare}%)"
          ></div>
        {/if}
      </div>

      <!-- Legend -->
      <div class="flex flex-wrap gap-x-4 gap-y-1 pt-1 text-xs text-slate-400">
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-full bg-emerald-400"></span>
          <span>{i18n.t.stats.taste.dropAnalytics.earlyDrop}</span>
          <span class="font-semibold text-slate-400 tabular-nums">{analytics.earlyDropCount}</span>
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-full bg-amber-400"></span>
          <span>{i18n.t.stats.taste.dropAnalytics.midDrop}</span>
          <span class="font-semibold text-slate-400 tabular-nums">{analytics.midDropCount}</span>
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-full bg-rose-400"></span>
          <span>{i18n.t.stats.taste.dropAnalytics.lateDrop}</span>
          <span class="font-semibold text-slate-400 tabular-nums">{analytics.lateDropCount}</span>
        </span>
      </div>
    </div>

    <!-- Top Reasons -->
    {#if analytics.topReasons.length > 0}
      <div class="mt-6 space-y-3 border-t border-white/5 pt-5">
        <span class="block text-xs font-semibold tracking-wider text-slate-400 uppercase">
          {i18n.t.stats.taste.dropAnalytics.topReasonsTitle}
        </span>

        <div class="space-y-2.5">
          {#each analytics.topReasons as stat (stat.reason)}
            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs">
                <span
                  class="truncate pr-2 font-medium text-slate-200"
                  title={getDropReasonLabel(stat.reason, i18n.current)}
                >
                  {getDropReasonLabel(stat.reason, i18n.current)}
                </span>
                <span class="shrink-0 font-medium text-slate-400 tabular-nums">
                  <span class="font-bold text-slate-200">{stat.count}</span> ({stat.percentage}%)
                </span>
              </div>
              <div class="h-2 w-full overflow-hidden rounded-full bg-white/5">
                <div
                  class="h-full rounded-full bg-rose-400/80 transition-[width] duration-300"
                  style="width: {stat.percentage}%;"
                ></div>
              </div>
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Insight quote -->
    <p
      class="mt-5 border-l-2 border-emerald-500/40 pl-3 text-sm leading-relaxed text-emerald-300/90"
    >
      {insightText}
    </p>
  {/if}
</div>
