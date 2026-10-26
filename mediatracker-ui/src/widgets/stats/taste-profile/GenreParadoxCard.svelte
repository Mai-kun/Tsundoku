<script lang="ts">
  import { Scale } from "$shared/ui/Icons.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { GenreCompletionStat } from "$shared/types";
  import { genreLabel } from "./genreLabel";

  interface Props {
    paradox: GenreCompletionStat[];
  }

  let { paradox }: Props = $props();
</script>

<div class="rounded-xl border border-white/5 bg-[#151a26] p-5">
  <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <Scale class="size-4 text-sky-400" aria-hidden="true" />
      <h3 class="text-base font-semibold tracking-tight text-white">
        {i18n.t.stats.taste.paradoxTitle}
      </h3>
    </div>
    <div class="flex items-center gap-3 text-[11px] text-slate-400">
      <span class="flex items-center gap-1.5">
        <span class="size-2 rounded-full bg-emerald-400"></span>
        {i18n.t.stats.taste.paradoxCompletion}
      </span>
      <span class="flex items-center gap-1.5">
        <span class="size-2 rounded-full bg-rose-400"></span>
        {i18n.t.stats.taste.paradoxDrop}
      </span>
    </div>
  </div>

  {#if paradox.length === 0}
    <p class="text-muted flex min-h-24 items-center justify-center text-xs">
      {i18n.t.stats.taste.emptyData}
    </p>
  {:else}
    <div class="space-y-3">
      {#each paradox as stat (stat.genre)}
        <div class="flex items-center gap-3">
          <span
            class="w-28 shrink-0 truncate text-sm font-medium text-slate-200"
            title={genreLabel(stat.genre)}
          >
            {genreLabel(stat.genre)}
          </span>
          <div class="min-w-0 flex-1 space-y-1">
            <div class="h-2.5 w-full overflow-hidden rounded-full bg-white/5">
              <div
                class="h-full rounded-full bg-emerald-400 transition-[width] duration-300"
                style="width: {stat.completionRate}%;"
              ></div>
            </div>
            <div class="h-2.5 w-full overflow-hidden rounded-full bg-white/5">
              <div
                class="h-full rounded-full bg-rose-400 transition-[width] duration-300"
                style="width: {stat.dropRate}%;"
              ></div>
            </div>
          </div>
          <div class="flex w-24 shrink-0 flex-col items-end text-[11px] leading-tight tabular-nums">
            <span class="text-emerald-300">{stat.completionRate}%</span>
            <span class="text-rose-300">{stat.dropRate}%</span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>
