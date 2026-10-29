<script lang="ts">
  import { Scale } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { AdvancedStats } from "$shared/types";
  import StaleBacklogModal from "$features/stale-triage/StaleBacklogModal.svelte";

  interface Props {
    stats: AdvancedStats;
    onMediaChanged?: () => void;
  }

  let { stats, onMediaChanged }: Props = $props();

  let showTriageModal = $state(false);

  const totalTitles = $derived(stats.totalTitles);
  const completedTitles = $derived(stats.completedTitles);

  const rawPlanned = $derived((stats as { plannedTitles?: number }).plannedTitles);

  const plannedCount = $derived(
    rawPlanned !== undefined ? Math.max(0, rawPlanned) : Math.max(0, totalTitles - completedTitles),
  );

  const inProgressCount = $derived(
    rawPlanned !== undefined ? Math.max(0, totalTitles - completedTitles - plannedCount) : 0,
  );

  const completedPercent = $derived(totalTitles > 0 ? (completedTitles / totalTitles) * 100 : 0);

  const plannedPercent = $derived(totalTitles > 0 ? (plannedCount / totalTitles) * 100 : 0);

  const inProgressPercent = $derived(totalTitles > 0 ? (inProgressCount / totalTitles) * 100 : 0);

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

<section class="mt-6 rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-4 flex items-center gap-2">
    <Scale class="size-4 text-emerald-400" aria-hidden="true" />
    <h3 class="text-base font-semibold tracking-tight text-white">
      {i18n.t.stats.backlogTitle}
    </h3>
  </div>

  <div class="flex h-3 w-full overflow-hidden rounded-full bg-white/5">
    {#if totalTitles === 0}
      <div class="h-full w-full bg-white/10"></div>
    {:else}
      {#if completedPercent > 0}
        <div
          class="h-full bg-[#10b981] first:rounded-l-full last:rounded-r-full"
          style="width: {completedPercent}%;"
          title={i18n.t.stats.segmentTooltip(
            i18n.t.stats.completed,
            completedTitles,
            Math.round(completedPercent),
          )}
        ></div>
      {/if}
      {#if inProgressPercent > 0}
        <div
          class="h-full bg-[#8b5cf6] first:rounded-l-full last:rounded-r-full"
          style="width: {inProgressPercent}%;"
          title={i18n.t.stats.segmentTooltip(
            i18n.t.stats.inProgress,
            inProgressCount,
            Math.round(inProgressPercent),
          )}
        ></div>
      {/if}
      {#if plannedPercent > 0}
        <div
          class="h-full bg-[#3b82f6] first:rounded-l-full last:rounded-r-full"
          style="width: {plannedPercent}%;"
          title={i18n.t.stats.segmentTooltip(
            i18n.t.stats.planned,
            plannedCount,
            Math.round(plannedPercent),
          )}
        ></div>
      {/if}
    {/if}
  </div>

  <div class="mt-3.5 flex flex-wrap items-center gap-4 text-xs sm:gap-6">
    <div class="flex items-center gap-2">
      <span class="size-2.5 shrink-0 rounded-full bg-[#10b981]"></span>
      <span class="text-slate-300">
        {i18n.t.stats.completed}:
        <span class="font-semibold text-white tabular-nums">{completedTitles}</span>
      </span>
    </div>
    <div class="flex items-center gap-2">
      <span class="size-2.5 shrink-0 rounded-full bg-[#8b5cf6]"></span>
      <span class="text-slate-300">
        {i18n.t.stats.inProgress}:
        <span class="font-semibold text-white tabular-nums">{inProgressCount}</span>
      </span>
    </div>
    <div class="flex items-center gap-2">
      <span class="size-2.5 shrink-0 rounded-full bg-[#3b82f6]"></span>
      <span class="text-slate-300">
        {i18n.t.stats.planned}:
        <span class="font-semibold text-white tabular-nums">{plannedCount}</span>
      </span>
    </div>
  </div>

  <div
    class="mt-4 rounded-lg border border-white/5 bg-white/[0.02] p-3.5 text-sm leading-relaxed text-slate-300"
  >
    {verdictText}
  </div>

  <div class="mt-3">
    <button
      type="button"
      class="text-accent hover:text-accent-hover inline-flex cursor-pointer items-center gap-1.5 text-xs font-medium transition"
      onclick={() => (showTriageModal = true)}
    >
      <span>{i18n.t.staleTriage.triageActionLink}</span>
    </button>
  </div>

  <StaleBacklogModal
    isOpen={showTriageModal}
    onClose={() => (showTriageModal = false)}
    onMediaChanged={() => {
      onMediaChanged?.();
    }}
  />
</section>
