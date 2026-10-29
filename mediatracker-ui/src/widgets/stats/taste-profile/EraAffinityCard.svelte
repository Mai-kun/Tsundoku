<script lang="ts">
  import { Crown } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { EraAffinityStat } from "$shared/types";

  interface Props {
    eras: EraAffinityStat[];
  }

  let { eras }: Props = $props();

  type EraKeys = keyof typeof i18n.t.stats.taste.eras;

  const maxPercentage = $derived(
    eras.length > 0 ? Math.max(...eras.map((era) => era.percentage), 0.01) : 1,
  );

  function eraLabel(era: string): string {
    return i18n.t.stats.taste.eras[era as EraKeys] ?? era;
  }
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-1 flex items-center gap-2">
    <Crown class="size-4 text-amber-400" aria-hidden="true" />
    <h3 class="text-base font-semibold tracking-tight text-white">{i18n.t.stats.taste.eraTitle}</h3>
  </div>
  <p class="mb-4 text-xs text-slate-400">{i18n.t.stats.taste.eraHint}</p>

  {#if eras.length === 0}
    <p class="text-muted flex min-h-24 items-center justify-center text-xs">
      {i18n.t.stats.taste.emptyData}
    </p>
  {:else}
    <div class="space-y-3">
      {#each eras as era, index (era.era)}
        <div class="flex items-center gap-3">
          <span class="w-24 shrink-0 text-sm font-medium text-slate-200">{eraLabel(era.era)}</span>
          <div class="h-2.5 min-w-0 flex-1 overflow-hidden rounded-full bg-white/5">
            <div
              class="h-full rounded-full transition-[width] duration-300"
              style="width: {(era.percentage / maxPercentage) * 100}%; background-color: {index %
                2 ===
              0
                ? '#5844e0'
                : '#818cf8'};"
            ></div>
          </div>
          <span class="w-24 shrink-0 text-right text-xs text-slate-400 tabular-nums">
            {era.count} · {era.percentage}%
          </span>
        </div>
      {/each}
    </div>
  {/if}
</div>
