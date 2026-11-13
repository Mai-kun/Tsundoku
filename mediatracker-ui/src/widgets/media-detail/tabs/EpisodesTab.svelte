<script lang="ts">
  import { slide } from "svelte/transition";
  import {
    ArrowUpDown,
    Check,
    CheckCircle2,
    Clock,
    Play,
  } from "$shared/ui/Icons";
  import { errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { TvSeason } from "$shared/types";
  import type { EpisodeRow, NextUp } from "$widgets/media-detail/detailTypes";

  interface Props {
    seasons: readonly TvSeason[];
    nextUp: NextUp | null;
    seriesEpisodes: { current: number; total: number };
    seriesProgressPercent: number;
    episodeBusy: unknown;
    progressError: unknown;
    sortOrder: "asc" | "desc";
    onToggleSort: () => void;
    /** Two-way: completes an unfinished season, rolls a finished one back to zero. */
    onToggleSeasonCompleteOf: (seasonId: string) => Promise<void>;
    onToggleEpisodeOf: (seasonId: string, number: number) => Promise<void>;
    /** Absolute per-season write used by the "watch up to this" hover action. */
    onSetSeasonProgressOf: (seasonId: string, number: number) => Promise<void>;
    /** Jumps to the next unwatched episode. */
    onWatchNextUp: (target: NextUp) => Promise<void>;
    /** Absolute series-wide counter (segment clicks distribute across seasons). */
    onSetSeriesCounter: (value: number) => void;
    onMarkAll: () => Promise<void>;
    onResetAll: () => Promise<void>;
    onOpenLists: () => void;
    formatDate: (value: string | null) => string;
    startedAt?: string | null;
    finishedAt?: string | null;
    /** Per-episode runtime (minutes) for the watched/remaining time captions. */
    episodeDuration?: number;
    /** Every season's episodes, keyed by season id. */
    episodesBySeason?: readonly {
      season: TvSeason;
      episodes: readonly EpisodeRow[];
    }[];
  }

  let {
    seasons,
    nextUp,
    seriesEpisodes,
    seriesProgressPercent,
    episodeBusy,
    progressError,
    sortOrder,
    onToggleSort,
    onToggleSeasonCompleteOf,
    onToggleEpisodeOf,
    onSetSeasonProgressOf,
    onWatchNextUp,
    onSetSeriesCounter,
    onMarkAll,
    onResetAll,
    onOpenLists,
    formatDate,
    startedAt = null,
    finishedAt = null,
    episodeDuration = 24,
    episodesBySeason = [],
  }: Props = $props();

  const SEGMENT_LIMIT = 60;
  const RING_RADIUS = 36;
  const RING_C = 2 * Math.PI * RING_RADIUS;
  const PACE_OPTIONS = [1, 2, 3, 5] as const;

  const isFinished = (season: TvSeason) =>
    season.totalEpisodes > 0 && (season.currentEpisode ?? 0) >= season.totalEpisodes;

  /** A season may legitimately have no episode count (extras, unannounced splits). */
  const seriesFinished = $derived(
    seasons.length > 0 &&
      seasons.every((season) => season.totalEpisodes <= 0 || isFinished(season)),
  );

  // ---------------- Summary header ----------------

  const pct = $derived(Math.min(100, Math.max(0, seriesProgressPercent)));

  const heading = $derived(
    seasons.length > 1
      ? i18n.t.episodes.seriesHeading(seasons.length)
      : seasons[0]
        ? i18n.t.progress.seasonN(seasons[0].seasonNumber)
        : "",
  );

  const watchedMinutes = $derived(seriesEpisodes.current * episodeDuration);
  const remainingEpisodes = $derived(Math.max(0, seriesEpisodes.total - seriesEpisodes.current));
  const remainingMinutes = $derived(remainingEpisodes * episodeDuration);

  function formatDuration(minutes: number): string {
    const hours = Math.floor(minutes / 60);
    const mins = Math.round(minutes % 60);
    if (hours > 0 && mins > 0) return i18n.t.progress.durationHM(hours, mins);
    if (hours > 0) return i18n.t.progress.durationH(hours);
    return i18n.t.progress.durationM(mins);
  }

  let pace = $state(2);
  const daysAtPace = $derived(pace > 0 && remainingEpisodes > 0 ? Math.ceil(remainingEpisodes / pace) : null);
  const finishEstimate = $derived.by(() => {
    if (daysAtPace === null) return null;
    const date = new Date(Date.now() + daysAtPace * 86_400_000);
    const label = new Intl.DateTimeFormat(i18n.current, { day: "numeric", month: "long" }).format(date);
    return i18n.t.progress.finishAt(label, daysAtPace);
  });

  // ---------------- Season bar ----------------

  interface Segment {
    seasonId: string;
    seasonNumber: number;
    episode: number;
    cumulative: number;
  }

  // Performance guard: short shows render every episode of every season as a segment;
  // long ones (60+) fall back to one proportional bar per season instead of hundreds of nodes.
  const segments = $derived.by((): Segment[] => {
    if (seriesEpisodes.total <= 0 || seriesEpisodes.total > SEGMENT_LIMIT) return [];
    const out: Segment[] = [];
    let cumulative = 0;
    for (const season of seasons) {
      if (season.totalEpisodes <= 0) continue;
      for (let episode = 1; episode <= season.totalEpisodes; episode += 1) {
        cumulative += 1;
        out.push({
          seasonId: season.id,
          seasonNumber: season.seasonNumber,
          episode,
          cumulative,
        });
      }
    }
    return out;
  });

  const seasonBars = $derived(
    seriesEpisodes.total > SEGMENT_LIMIT
      ? seasons.filter((season) => season.totalEpisodes > 0)
      : [],
  );

  function clickSegment(segment: Segment) {
    // Clicking the last watched segment unwatches it; anything else marks through it.
    const target =
      segment.cumulative === seriesEpisodes.current ? segment.cumulative - 1 : segment.cumulative;
    onSetSeriesCounter(Math.max(0, target));
  }

  function clickSeasonBar(season: TvSeason, event: MouseEvent) {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    if (rect.width <= 0) return;
    const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
    const value = Math.round(ratio * season.totalEpisodes);
    if (value === (season.currentEpisode ?? 0)) return;
    void onSetSeasonProgressOf(season.id, value);
  }

  // ---------------- Season ribbon + active season ----------------

  let activeSeasonId = $state("");

  $effect(() => {
    void seasons;
    if (seasons.length === 0) return;
    if (seasons.some((season) => season.id === activeSeasonId)) return;
    const firstUnwatched = seasons.find(
      (season) => season.totalEpisodes > 0 && (season.currentEpisode ?? 0) < season.totalEpisodes,
    );
    activeSeasonId = (firstUnwatched ?? seasons[0]).id;
  });

  const activeSeason = $derived(
    seasons.find((season) => season.id === activeSeasonId) ?? seasons[0] ?? null,
  );

  // ---------------- Filters + episode list ----------------

  type EpisodeFilter = "all" | "unwatched" | "watched";
  let filter = $state<EpisodeFilter>("all");

  const activeRowsRaw = $derived(
    activeSeason
      ? (episodesBySeason.find((view) => view.season.id === activeSeason.id)?.episodes ?? [])
      : [],
  );
  const activeAll = $derived(activeRowsRaw.length);
  const activeWatchedCount = $derived(activeRowsRaw.filter((row) => row.watched).length);
  const activeUnwatchedCount = $derived(activeAll - activeWatchedCount);
  const activeRows = $derived.by(() => {
    const ordered = sortOrder === "asc" ? activeRowsRaw : [...activeRowsRaw].reverse();
    if (filter === "watched") return ordered.filter((row) => row.watched);
    if (filter === "unwatched") return ordered.filter((row) => !row.watched);
    return ordered;
  });

  // The source often stamps every episode with the series premiere date: only show per-episode
  // dates when this season's list actually carries distinct ones.
  const activeDatesVary = $derived.by(() => {
    const dates = activeRowsRaw.map((row) => row.airDate).filter((date): date is string => Boolean(date));
    return dates.length > 0 && new Set(dates).size > 1;
  });

  // "Episode 1 - ..." repeats the number already shown in the E-badge. The pattern lives in the
  // dictionary because its alternatives are locale-specific words.
  const titlePrefixRe = $derived(new RegExp(i18n.t.episodes.titlePrefixPattern, "i"));
  function cleanEpisodeTitle(title: string): string {
    const cleaned = title.replace(titlePrefixRe, "").trim();
    return cleaned || title;
  }

  // ---------------- Reset guard: the destructive action needs a second tap ----------------

  let resetArmed = $state(false);
  let resetTimer: ReturnType<typeof setTimeout> | null = null;

  function requestReset() {
    if (!resetArmed) {
      resetArmed = true;
      if (resetTimer) clearTimeout(resetTimer);
      resetTimer = setTimeout(() => (resetArmed = false), 4000);
      return;
    }
    resetArmed = false;
    if (resetTimer) clearTimeout(resetTimer);
    void onResetAll();
  }

  $effect(() => {
    return () => {
      if (resetTimer) clearTimeout(resetTimer);
    };
  });

  const isNextUp = (episode: EpisodeRow) =>
    nextUp !== null && nextUp.seasonId === activeSeason?.id && nextUp.episodeNumber === episode.number;

  const filters: ReadonlyArray<{ key: EpisodeFilter; label: string; count: number }> = $derived([
    { key: "all", label: i18n.t.episodes.filterAll, count: activeAll },
    { key: "unwatched", label: i18n.t.episodes.filterUnwatched, count: activeUnwatchedCount },
    { key: "watched", label: i18n.t.episodes.filterWatched, count: activeWatchedCount },
  ]);
</script>

{#if seasons.length > 0}
  <div class="space-y-4">
    {#if progressError}
      <p class="text-xs text-rose-300" role="alert">
        {errorMessage(progressError)}
      </p>
    {/if}

    <!-- 1. Series summary card: ring, counter, next-episode action, season segments. -->
    <section
      class="space-y-3 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
    >
      <div class="flex items-center gap-4">
        <div class="relative size-20 shrink-0">
          <svg viewBox="0 0 80 80" class="size-full -rotate-90" aria-hidden="true">
            <circle
              cx="40"
              cy="40"
              r={RING_RADIUS}
              fill="none"
              stroke-width="7"
              class="stroke-white/[0.07]"
            />
            <circle
              cx="40"
              cy="40"
              r={RING_RADIUS}
              fill="none"
              stroke-width="7"
              stroke-linecap="round"
              class="stroke-[#8b7cf6]"
              stroke-dasharray={RING_C}
              stroke-dashoffset={RING_C * (1 - pct / 100)}
              style="transition: stroke-dashoffset 300ms ease;"
            />
          </svg>
          <span
            class="absolute inset-0 grid place-items-center text-sm font-bold text-white tabular-nums"
          >
            {Math.round(pct)}%
          </span>
        </div>

        <div class="min-w-0 flex-1">
          <p class="text-xs font-bold tracking-wider text-slate-300 uppercase">{heading}</p>
          <p class="mt-0.5 text-[30px] leading-none font-extrabold text-white tabular-nums">
            {seriesEpisodes.current}
            <span class="text-muted text-lg font-semibold">
              / {seriesEpisodes.total} {i18n.t.progress.unitShortEp}
            </span>
          </p>
        </div>

        <div class="flex shrink-0 items-center gap-1.5">
          {#if nextUp}
            <button
              type="button"
              class="tap flex h-9 cursor-pointer items-center gap-1.5 rounded-lg bg-[#8b7cf6] px-3.5 text-xs font-bold text-white transition hover:bg-[#7b6cea] disabled:cursor-not-allowed disabled:opacity-60"
              disabled={Boolean(episodeBusy)}
              title={i18n.t.detail.bannerNextEpisode}
              onclick={() => void onWatchNextUp(nextUp)}
            >
              <Play size={13} stroke-width={2.5} aria-hidden="true" />
              {i18n.t.detail.bannerNextEpisode} S{nextUp.seasonNumber}E{nextUp.episodeNumber}
            </button>
          {:else if seriesFinished}
            <span
              class="inline-flex h-9 items-center gap-1.5 rounded-lg border border-emerald-400/30 bg-emerald-400/10 px-3 text-xs font-bold text-emerald-300"
            >
              <CheckCircle2 size={14} aria-hidden="true" />
              {i18n.t.detail.bannerCompleted}
            </span>
          {/if}
          <button
            type="button"
            class="tap h-9 cursor-pointer rounded-lg border border-white/10 px-2.5 text-xs font-semibold text-slate-300 transition hover:bg-white/[0.06] hover:text-white disabled:cursor-not-allowed disabled:opacity-60"
            disabled={seriesFinished || Boolean(episodeBusy)}
            title={i18n.t.episodes.markAll}
            aria-label={i18n.t.episodes.markAll}
            onclick={() => void onMarkAll()}
          >
            {i18n.t.episodes.markAll}
          </button>
        </div>
      </div>

      {#if segments.length > 0}
        <!-- Segmented season bar: full card width; season groups share it proportionally to
             their episode counts, one segment per episode. -->
        <div class="my-4 flex w-full gap-2">
          {#each seasons as season (season.id)}
            {#if season.totalEpisodes > 0}
              <div class="flex min-w-0 items-center gap-[3px]" style={`flex: ${season.totalEpisodes}`}>
                {#each segments.filter((seg) => seg.seasonId === season.id) as seg (seg.cumulative)}
                  <button
                    type="button"
                    class={`h-2.5 flex-1 cursor-pointer rounded-[3px] transition-colors ${
                      seg.cumulative <= seriesEpisodes.current
                        ? "bg-[#7c6cf6]"
                        : seg.cumulative === seriesEpisodes.current + 1
                          ? "animate-pulse bg-[#8b7cf6]/50 ring-[1.5px] ring-[#8b7cf6]"
                          : "bg-[#222536] hover:bg-white/20"
                    }`}
                    title={`S${seg.seasonNumber}E${seg.episode}`}
                    aria-label={`S${seg.seasonNumber}E${seg.episode}`}
                    onclick={() => clickSegment(seg)}
                  ></button>
                {/each}
              </div>
            {/if}
          {/each}
        </div>
      {:else if seasonBars.length > 0}
        <!-- Long show: one proportional bar per season instead of hundreds of segments. -->
        <div class="my-4 flex w-full items-center gap-2">
          {#each seasonBars as season (season.id)}
            <button
              type="button"
              class="relative h-2.5 min-w-0 cursor-pointer overflow-hidden rounded-[4px] bg-[#222536] transition hover:bg-white/20"
              style={`flex-grow: ${season.totalEpisodes}; flex-basis: 0;`}
              title={`${i18n.t.progress.seasonN(season.seasonNumber)} · ${season.currentEpisode ?? 0}/${season.totalEpisodes}`}
              onclick={(e) => clickSeasonBar(season, e)}
            >
              <span
                class={`absolute inset-y-0 left-0 block rounded-[4px] transition-[width] duration-200 ${
                  isFinished(season) ? "w-full bg-emerald-400/70" : "bg-[#7c6cf6]"
                }`}
                style={`width: ${((season.currentEpisode ?? 0) / season.totalEpisodes) * 100}%`}
              ></span>
            </button>
          {/each}
        </div>
      {/if}

      <!-- Stats grouped left; the uniform per-episode runtime rides on the right, once. -->
      <div class="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs">
        <span class="text-muted tabular-nums">
          {i18n.t.progress.watchedVerb}
          <span class="font-semibold text-slate-200">{formatDuration(watchedMinutes)}</span>
        </span>
        <span class="text-muted tabular-nums">
          {i18n.t.progress.remainingTimeLabel}
          <span class="font-semibold text-slate-200">{formatDuration(remainingMinutes)}</span>
        </span>
        <span class="text-muted">
          {i18n.t.detail.startedLabel}:
          <span class="text-slate-200">{formatDate(startedAt)}</span>
        </span>
        {#if finishedAt}
          <span class="text-muted">
            {i18n.t.detail.endedLabel}:
            <span class="text-slate-200">{formatDate(finishedAt)}</span>
          </span>
        {/if}
        {#if episodeDuration > 0}
          <span class="text-muted ml-auto tabular-nums">
            {episodeDuration} {i18n.t.detail.minPerEp}
          </span>
        {/if}
      </div>

      {#if remainingEpisodes > 0}
        <!-- Pace forecast lives on its own separated row: it is a tool, not a fact. -->
        <div class="mt-3 flex flex-wrap items-center gap-1.5 border-t border-white/5 pt-3 text-xs">
          <Clock size={13} class="shrink-0 text-[#8b7cf6]" aria-hidden="true" />
          <span class="text-muted">{i18n.t.progress.paceLabel}:</span>
          {#each PACE_OPTIONS as p (p)}
            <button
              type="button"
              class={`flex h-5 min-w-6 cursor-pointer items-center justify-center rounded border px-1 text-[10px] font-bold tabular-nums transition ${
                pace === p
                  ? "border-[#8b7cf6]/60 bg-[#8b7cf6]/15 text-[#8b7cf6]"
                  : "border-white/10 text-slate-400 hover:bg-white/5 hover:text-white"
              }`}
              aria-pressed={pace === p}
              onclick={() => (pace = p)}
            >
              {p}
            </button>
          {/each}
          <span class="text-muted">{i18n.t.episodes.perDay}</span>
          {#if finishEstimate}
            <span class="text-slate-300">→ {finishEstimate}</span>
          {/if}
        </div>
      {/if}
    </section>

    <!-- 2. Season ribbon: compact switchers with a 4px progress rail. -->
    {#if seasons.length > 1}
      <div class="thin-scroll flex gap-2 overflow-x-auto pb-1">
        {#each seasons as season (season.id)}
          <button
            type="button"
            class={`w-28 shrink-0 cursor-pointer rounded-lg border px-3 py-2 text-left transition ${
              season.id === activeSeasonId
                ? "border-[#8b7cf6]/50 bg-[#8b7cf6]/10"
                : "border-white/[0.06] bg-[var(--color-panel-line)] hover:border-white/10 hover:bg-white/[0.04]"
            }`}
            onclick={() => (activeSeasonId = season.id)}
          >
            <span class="block truncate text-xs font-bold text-white">
              {i18n.t.progress.seasonN(season.seasonNumber)}
            </span>
            <span class="text-muted block text-[11px] tabular-nums">
              {i18n.t.card.episodes(season.currentEpisode, season.totalEpisodes)}
            </span>
            <span class="mt-1.5 block h-1 w-full overflow-hidden rounded-full bg-white/[0.08]">
              <span
                class={`block h-full rounded-full transition-[width] duration-200 ${
                  isFinished(season) ? "w-full bg-emerald-400" : "bg-[#8b7cf6]"
                }`}
                style={`width: ${
                  season.totalEpisodes > 0
                    ? Math.min(100, ((season.currentEpisode ?? 0) / season.totalEpisodes) * 100)
                    : 0
                }%`}
              ></span>
            </span>
          </button>
        {/each}
      </div>
    {/if}

    <!-- 3. Filters + mass actions for the active season. -->
    <div
      class="flex flex-wrap items-center gap-2 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] px-3.5 py-2.5"
    >
      {#each filters as f (f.key)}
        <button
          type="button"
          class={`cursor-pointer rounded-full px-2.5 py-1 text-xs font-semibold transition ${
            filter === f.key
              ? "bg-[#8b7cf6]/15 text-[#8b7cf6]"
              : "text-slate-400 hover:bg-white/[0.06] hover:text-white"
          }`}
          aria-pressed={filter === f.key}
          onclick={() => (filter = f.key)}
        >
          {f.label} ({f.count})
        </button>
      {/each}

      <div class="ml-auto flex items-center gap-2">
        <button
          type="button"
          class="bg-surface/50 inline-flex h-7 cursor-pointer items-center gap-1 rounded-md border border-white/[0.08] px-2 text-xs font-medium text-white transition hover:bg-white/10"
          onclick={onToggleSort}
          title={i18n.t.episodes.sortTitle}
        >
          <ArrowUpDown size={12} class="text-[#8b7cf6]" aria-hidden="true" />
          {sortOrder === "asc" ? i18n.t.episodes.sortOldFirst : i18n.t.episodes.sortNewFirst}
        </button>
        {#if activeSeason && seasons.length > 1}
          <button
            type="button"
            class={`text-xs font-semibold transition hover:underline disabled:cursor-not-allowed disabled:opacity-60 ${
              isFinished(activeSeason) ? "text-slate-400 hover:text-white" : "text-emerald-300"
            }`}
            disabled={Boolean(episodeBusy) || activeSeason.totalEpisodes <= 0}
            onclick={() => void onToggleSeasonCompleteOf(activeSeason.id)}
          >
            {isFinished(activeSeason)
              ? i18n.t.episodes.unmarkSeason
              : i18n.t.episodes.markSeason}
          </button>
        {/if}
        {#if resetArmed}
          <!-- Two-tap destructive guard: first tap arms, the second one within 4s fires. -->
          <span class="flex items-center gap-1.5">
            <button
              type="button"
              class="cursor-pointer rounded-md border border-rose-500/40 bg-rose-500/15 px-2 py-1 text-xs font-bold text-rose-300 transition hover:bg-rose-500/25 disabled:cursor-not-allowed disabled:opacity-60"
              disabled={seriesEpisodes.current === 0 || Boolean(episodeBusy)}
              onclick={requestReset}
            >
              {i18n.t.episodes.confirmReset}
            </button>
            <button
              type="button"
              class="text-muted cursor-pointer text-xs transition hover:text-white"
              onclick={() => (resetArmed = false)}
            >
              {i18n.t.common.cancel}
            </button>
          </span>
        {:else}
          <button
            type="button"
            class="text-muted cursor-pointer text-xs transition hover:text-rose-300 disabled:cursor-not-allowed disabled:opacity-60"
            disabled={seriesEpisodes.current === 0 || Boolean(episodeBusy)}
            title={i18n.t.episodes.resetAll}
            onclick={requestReset}
          >
            {i18n.t.episodes.resetAll}
          </button>
        {/if}
      </div>
    </div>

    <!-- 4. Episode list of the active season. -->
    <section class="space-y-1.5">
      {#if activeRows.length === 0}
        <p class="text-muted rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] px-4 py-6 text-center text-sm">
          {activeAll === 0 ? i18n.t.episodes.noEpisodes : i18n.t.common.noData}
        </p>
      {:else}
        <div class="thin-scroll max-h-[560px] space-y-1.5 overflow-y-auto pr-1">
          {#each activeRows as episode (episode.id)}
            {@render episodeRow(episode)}
          {/each}
        </div>
      {/if}
    </section>
  </div>
{/if}

{#snippet episodeRow(episode: EpisodeRow)}
  {@const watched = episode.watched}
  {@const next = isNextUp(episode)}
  <div
    class={`group flex items-center gap-3 rounded-lg border px-3 py-2 transition ${
      next
        ? "border-[#8b7cf6]/30 bg-[#8b7cf6]/[0.06]"
        : "border-white/[0.05] bg-[var(--color-panel-line)] hover:bg-[var(--color-panel-raised)]"
    }`}
  >
    <span
      class={`grid size-9 shrink-0 place-items-center rounded-lg text-xs font-bold tabular-nums ${
        next
          ? "bg-[#8b7cf6] text-white"
          : watched
            ? "bg-white/[0.05] text-[var(--color-muted)]"
            : "bg-[var(--color-field)] text-slate-300"
      }`}
    >
      E{episode.number}
    </span>
    <div class="min-w-0 flex-1">
      <div class="flex items-center gap-2">
        <p
          class={`truncate text-sm font-semibold ${watched ? "text-muted line-through" : "text-white"}`}
          title={episode.title}
        >
          {cleanEpisodeTitle(episode.title)}
        </p>
        {#if next}
          <span
            class="shrink-0 rounded-full border border-[#8b7cf6]/40 bg-[#8b7cf6]/15 px-1.5 py-0.5 text-[10px] font-bold text-[#8b7cf6]"
          >
            {i18n.t.episodes.nextBadge}
          </span>
        {/if}
      </div>
      {#if activeDatesVary && episode.airDate}
        <p class="text-muted mt-0.5 truncate text-[11px]">
          {formatDate(episode.airDate)}
        </p>
      {/if}
    </div>

    {#if !watched}
      <button
        type="button"
        class="shrink-0 cursor-pointer rounded-md border border-white/10 px-2 py-1 text-[11px] font-medium text-slate-300 transition hover:bg-white/[0.08] hover:text-white focus-visible:opacity-100 max-md:opacity-100 md:opacity-0 md:group-hover:opacity-100"
        disabled={Boolean(episodeBusy)}
        title={i18n.t.episodes.markUpTo}
        onclick={() => void onSetSeasonProgressOf(activeSeason?.id ?? "", episode.number)}
      >
        ✓ {i18n.t.episodes.markUpTo}
      </button>
    {/if}

    <button
      type="button"
      class={`grid size-8 shrink-0 cursor-pointer place-items-center rounded-full border transition active:scale-95 disabled:cursor-wait disabled:opacity-60 ${
        watched
          ? "border-emerald-400/40 bg-emerald-400/20 text-emerald-400 hover:bg-emerald-400/30"
          : "border-white/[0.12] bg-[var(--color-field)] hover:border-emerald-400/40"
      }`}
      aria-label={watched ? i18n.t.detail.unwatchAction : i18n.t.detail.markWatched}
      title={watched ? i18n.t.detail.unwatchAction : i18n.t.detail.markWatched}
      disabled={Boolean(episodeBusy)}
      onclick={() => void onToggleEpisodeOf(activeSeason?.id ?? "", episode.number)}
    >
      {#if watched}
        <Check size={15} stroke-width={2.8} aria-hidden="true" />
      {/if}
    </button>
  </div>
{/snippet}
