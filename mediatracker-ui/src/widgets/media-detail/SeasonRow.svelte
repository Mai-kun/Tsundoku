<script lang="ts">
  import { Image as ImageIcon, Minus, Plus } from "$shared/ui/Icons";
  import { untrack } from "svelte";
  import { errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import { clampProgress } from "$entities/media/model/progressRules";
  import type { TvSeason } from "$shared/types";
  import { createProgressDebounce } from "$shared/utils/progressDebounce";

  interface Props {
    season: TvSeason;
    onProgress: (id: string, currentEpisode: number) => Promise<void>;
    onProgressCommitted: () => void;
  }

  let { season, onProgress, onProgressCommitted }: Props = $props();

  let trackedSeason: TvSeason | null = null;
  let currentEpisode = $state(untrack(() => season.currentEpisode));
  let committedEpisode = $state(untrack(() => season.currentEpisode));
  let pendingSnapshot = $state<number | null>(null);

  let mutationError = $state<unknown>(null);
  const progressDebounce = createProgressDebounce({
    send: (id, value) => onProgress(id, value),
    buildRequest: (id, value) => ({
      url: `/api/seasons/${id}/progress`,
      body: { currentEpisode: value },
    }),
    onCommitted: (value) => {
      committedEpisode = value;
      if (currentEpisode === value) onProgressCommitted();
    },
    onError: (error) => {
      currentEpisode = pendingSnapshot ?? committedEpisode;
      committedEpisode = currentEpisode;
      pendingSnapshot = null;
      mutationError = error;
    },
  });

  $effect(() => {
    if (season !== trackedSeason) {
      trackedSeason = season;
      currentEpisode = season.currentEpisode;
      committedEpisode = season.currentEpisode;
      pendingSnapshot = null;
    }
  });

  $effect(() => {
    return () => void progressDebounce.flush(true);
  });

  function format(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value);
  }

  function scheduleProgress(delta: number) {
    const next = clampProgress(currentEpisode + delta, season.totalEpisodes);
    if (next === currentEpisode) return;

    if (pendingSnapshot === null) {
      pendingSnapshot = committedEpisode;
    }

    currentEpisode = next;
    mutationError = null;
    progressDebounce.schedule(season.id, next);
  }
</script>

<article class="bg-card grid gap-4 rounded-lg p-3 sm:grid-cols-[5rem_1fr_auto] sm:items-center">
  <div class="bg-canvas aspect-[3/4] w-20 overflow-hidden rounded-md sm:w-full">
    {#if season.coverUrl}
      <img
        src={season.coverUrl}
        alt={season.title}
        class="h-full w-full object-cover"
        loading="lazy"
        decoding="async"
      />
    {:else}
      <div
        class="from-panel to-elevated text-muted grid h-full place-items-center bg-gradient-to-br"
      >
        <ImageIcon size={24} stroke-width={1.25} aria-hidden="true" />
      </div>
    {/if}
  </div>

  <div class="min-w-0 space-y-2">
    <div>
      <p class="text-accent-soft text-[10px] font-bold tracking-[0.16em] uppercase">
        {i18n.t.createModal.fields.season}
        {season.seasonNumber}
      </p>
      <h2 class="text-ink truncate text-sm font-semibold" title={season.title}>
        {season.title}
      </h2>
    </div>
    <div class="space-y-1.5">
      <div class="text-muted flex items-center justify-between gap-3 text-xs">
        <span>{i18n.t.card.episodes(currentEpisode, season.totalEpisodes)}</span>
        <span>{format(currentEpisode)} / {format(season.totalEpisodes)}</span>
      </div>
      {#if season.totalEpisodes > 0}
        <div class="bg-canvas h-1.5 overflow-hidden rounded-full">
          <div
            class="bg-accent h-full w-full origin-left rounded-full transition-transform duration-200"
            style={`transform: scaleX(${Math.min(currentEpisode / season.totalEpisodes, 1)})`}
          ></div>
        </div>
      {/if}
    </div>
    {#if mutationError}
      <p class="text-xs text-rose-300" role="alert">
        {errorMessage(mutationError)}
      </p>
    {/if}
  </div>

  <div class="bg-canvas flex h-9 items-center self-end rounded-md sm:self-auto">
    <button
      type="button"
      class="tap text-muted hover:bg-panel hover:text-ink grid h-full w-9 place-items-center rounded-l-md transition"
      aria-label={i18n.t.card.decrement}
      onclick={() => scheduleProgress(-1)}><Minus size={15} aria-hidden="true" /></button
    >
    <span class="text-ink min-w-10 px-2 text-center text-xs font-semibold tabular-nums"
      >{format(currentEpisode)}</span
    >
    <button
      type="button"
      class="tap text-muted hover:bg-panel hover:text-ink grid h-full w-9 place-items-center rounded-r-md transition"
      aria-label={i18n.t.card.increment}
      onclick={() => scheduleProgress(1)}><Plus size={15} aria-hidden="true" /></button
    >
  </div>
</article>
