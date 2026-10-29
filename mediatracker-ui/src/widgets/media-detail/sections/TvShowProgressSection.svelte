<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import { Clock, Minus, Plus } from "$shared/ui/Icons";
  import { formatNumber } from "$entities/media/model/mediaLabels";
  import { errorMessage } from "$shared/api/api";
  import type { ProgressInfo } from "../detailTypes";
  import type { MediaDetail, TvShowMedia, TvSeason } from "$shared/types";

  interface Props {
    media: MediaDetail;
    totalEpisodes: number;
    watchedEpisodes: number;
    progress: ProgressInfo;
    value: number;
    percent: number;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let {
    media,
    totalEpisodes,
    watchedEpisodes,
    progress,
    value,
    percent,
    error,
    onStep,
    onCounterChange,
  }: Props = $props();

  const tvMedia = $derived(media as unknown as TvShowMedia);
  const duration = $derived(tvMedia.episodeDurationMinutes || tvMedia.durationMinutes || 24);
  const DAILY_PACE = 2;

  /** All seasons of the show, when the detail payload carried them. */
  const seasons = $derived((media as { seasons?: TvSeason[] }).seasons ?? []);
  /** "Season 1: 220 · Season 2: 280" — shown only when the total spans several seasons. */
  const seasonBreakdown = $derived(
    seasons.length > 1
      ? seasons.map((s) => `Season ${s.seasonNumber}: ${formatNumber(s.totalEpisodes)}`).join(" · ")
      : null,
  );

  const effectiveTotal = $derived(totalEpisodes > 0 ? totalEpisodes : (progress.total ?? 0));
  const effectiveWatched = $derived(value);
  const remainingEpisodes = $derived(Math.max(0, effectiveTotal - effectiveWatched));

  const totalHours = $derived(((effectiveTotal * duration) / 60).toFixed(1));
  const watchedHours = $derived(((effectiveWatched * duration) / 60).toFixed(1));
  const remainingHours = $derived(((remainingEpisodes * duration) / 60).toFixed(1));
  const daysAtPace = $derived(Math.ceil(remainingEpisodes / DAILY_PACE));

  const isRu = $derived(i18n.current === "ru");

  let isEditing = $state(false);
  let editValue = $state("");
  let isDragging = $state(false);
  let barElement: HTMLElement | null = $state(null);

  function focusOnMount(el: HTMLElement) {
    el.focus();
    if (el instanceof HTMLInputElement) el.select();
  }

  function applyValue(nextVal: number) {
    const clamped = Math.max(0, effectiveTotal > 0 ? Math.min(nextVal, effectiveTotal) : nextVal);
    if (clamped === value) return;
    if (onCounterChange) {
      onCounterChange(clamped);
    } else {
      onStep(clamped - value);
    }
  }

  function startEditing() {
    editValue = String(value);
    isEditing = true;
  }

  function commitEditing() {
    if (!isEditing) return;
    isEditing = false;
    const parsed = parseInt(editValue, 10);
    if (!isNaN(parsed)) {
      applyValue(parsed);
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === "Enter") {
      commitEditing();
    } else if (e.key === "Escape") {
      isEditing = false;
    }
  }

  function calculateValueFromPointer(clientX: number): number {
    if (!barElement || effectiveTotal <= 0) return value;
    const rect = barElement.getBoundingClientRect();
    if (rect.width <= 0) return value;
    const offsetX = Math.max(0, Math.min(clientX - rect.left, rect.width));
    const ratio = offsetX / rect.width;
    return Math.round(ratio * effectiveTotal);
  }

  function handlePointerDown(e: PointerEvent) {
    if (effectiveTotal <= 0) return;
    isDragging = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    applyValue(calculateValueFromPointer(e.clientX));
  }

  function handlePointerMove(e: PointerEvent) {
    if (!isDragging || effectiveTotal <= 0) return;
    applyValue(calculateValueFromPointer(e.clientX));
  }

  function handlePointerUp(e: PointerEvent) {
    if (isDragging) {
      isDragging = false;
      try {
        (e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
      } catch {}
    }
  }
</script>

<section
  class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm"
>
  <!-- 1. Верхняя строка: СЕРИИ, счетчик и капсула кнопок -->
  <div class="flex items-center justify-between gap-3">
    <div class="flex min-w-0 flex-wrap items-center gap-2.5">
      <span class="text-xs font-bold tracking-wider text-slate-300 uppercase">
        {isRu ? "СЕРИИ" : "EPISODES"}
      </span>
      <div class="flex items-center gap-1.5">
        {#if isEditing}
          <input
            type="number"
            min="0"
            max={effectiveTotal > 0 ? effectiveTotal : undefined}
            class="border-accent focus:border-accent h-7 w-16 rounded-lg border bg-black/60 px-1 text-center text-lg font-black text-white tabular-nums ring-0 outline-none"
            bind:value={editValue}
            onblur={commitEditing}
            onkeydown={handleKeydown}
            use:focusOnMount
          />
        {:else}
          <button
            type="button"
            class="hover:text-accent-soft cursor-pointer text-xl font-black text-white tabular-nums transition"
            onclick={startEditing}
            title={isRu ? "Нажмите для ручного ввода" : "Click to enter number"}
          >
            {formatNumber(value)}
          </button>
        {/if}
        {#if effectiveTotal > 0}
          <span class="text-muted text-xs font-bold tabular-nums">
            / {formatNumber(effectiveTotal)}
          </span>
          <span
            class="bg-accent-soft/10 text-accent-soft rounded-full px-2 py-0.5 text-xs font-bold tabular-nums"
          >
            {Math.round(percent)}%
          </span>
        {/if}
        {#if seasonBreakdown}
          <div class="text-muted mt-0.5 text-[11px]">
            {isRu ? "Всего серий" : "Total episodes"}: {formatNumber(effectiveTotal)}
            ({seasonBreakdown})
          </div>
        {/if}
      </div>
    </div>

    <!-- Компактная сгруппированная капсула кнопок -->
    <div class="flex shrink-0 items-center gap-1.5">
      <button
        type="button"
        class="grid h-8 w-8 cursor-pointer place-items-center rounded-lg border border-white/10 bg-[var(--color-field)] text-slate-300 transition hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
        aria-label={i18n.t.card.decrement}
        disabled={value <= 0}
        onclick={() => onStep(-1)}
      >
        <Minus size={15} aria-hidden="true" />
      </button>
      <button
        type="button"
        class="bg-accent/20 border-accent/40 text-accent-soft hover:bg-accent flex h-8 cursor-pointer items-center justify-center rounded-lg border px-2.5 text-xs font-bold transition hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
        aria-label="+1"
        disabled={effectiveTotal > 0 && value >= effectiveTotal}
        onclick={() => onStep(1)}
      >
        +1
      </button>
      {#if effectiveTotal === 0 || effectiveTotal - value >= 5}
        <button
          type="button"
          class="flex h-8 cursor-pointer items-center justify-center rounded-lg border border-white/10 bg-[var(--color-field)] px-2 text-xs font-bold text-slate-300 transition hover:bg-white/10 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
          aria-label="+5"
          disabled={effectiveTotal > 0 && value >= effectiveTotal}
          onclick={() => onStep(5)}
        >
          +5
        </button>
      {/if}
    </div>
  </div>

  <!-- 2. Интерактивная шкала-прогрессбар -->
  {#if effectiveTotal > 0}
    <div
      bind:this={barElement}
      role="slider"
      tabindex="0"
      aria-label={isRu ? "Прогресс серий" : "Episode progress"}
      aria-valuenow={value}
      aria-valuemin="0"
      aria-valuemax={effectiveTotal}
      class="relative h-2.5 w-full cursor-pointer touch-none overflow-hidden rounded-full border border-white/[0.06] bg-[var(--color-field)] shadow-inner select-none"
      onpointerdown={handlePointerDown}
      onpointermove={handlePointerMove}
      onpointerup={handlePointerUp}
      onpointercancel={handlePointerUp}
    >
      <div
        class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#818cf8] shadow-[0_0_8px_rgba(129,140,248,0.4)] transition-[width] duration-150 ease-out"
        style="width: {Math.min(100, Math.max(0, percent))}%"
      ></div>
    </div>
  {/if}

  {#if error}
    <p class="text-xs text-rose-300" role="alert">
      {errorMessage(error)}
    </p>
  {/if}

  <!-- 3. Блок аналитики времени просмотра -->
  {#if effectiveTotal > 0}
    <div class="grid grid-cols-3 gap-2 pt-1 text-xs">
      <div
        class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2"
      >
        <span class="text-muted truncate">{isRu ? "Всего времени" : "Total time"}</span>
        <span class="font-semibold text-white">~{totalHours} {isRu ? "ч." : "h"}</span>
      </div>
      <div
        class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2"
      >
        <span class="text-muted truncate">{isRu ? "Просмотрено" : "Watched"}</span>
        <span class="font-semibold text-white">~{watchedHours} {isRu ? "ч." : "h"}</span>
      </div>
      <div
        class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2"
      >
        <span class="text-muted truncate">{isRu ? "Осталось" : "Remaining"}</span>
        <span class="font-semibold text-white">~{remainingHours} {isRu ? "ч." : "h"}</span>
      </div>
    </div>

    <div class="text-muted flex items-center justify-between text-[11px]">
      <span>
        {isRu ? "Хронометраж серии:" : "Episode duration:"}
        <strong class="font-medium text-slate-300">~{duration} {isRu ? "мин." : "min"}</strong>
      </span>
    </div>

    {#if remainingEpisodes > 0}
      <div class="text-muted flex items-center gap-2 text-xs">
        <Clock size={13} class="text-accent-soft shrink-0" />
        <span>
          {isRu
            ? `При темпе ${DAILY_PACE} эп./день просмотр займет ~${daysAtPace} дн.`
            : `At ${DAILY_PACE} ep./day watching will take ~${daysAtPace} days`}
        </span>
      </div>
    {:else}
      <div class="text-xs font-semibold text-emerald-400">
        {isRu ? "✓ Все серии просмотрены!" : "✓ All episodes watched!"}
      </div>
    {/if}
  {/if}
</section>
