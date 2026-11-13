<script lang="ts">
  import { Check, Minus, Plus } from "$shared/ui/Icons";
  import { untrack } from "svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { formatNumber } from "$entities/media/model/mediaLabels";
  import { errorMessage } from "$shared/api/api";

  export type ProgressAccent = "indigo" | "amber" | "teal" | "theme";

  interface Props {
    /** Uppercase section label: episodes / chapters / pages / hours. */
    label: string;
    value: number;
    /** 0 means "unknown" (games): no ring, no bar, no time math. */
    total: number;
    percent: number;
    /** Short unit after the total: ep. / ch. / pp. / h. */
    unitShort: string;
    /** Caption verb for the consumed side: watched / read / played. */
    doneLabel: string;
    remainLabel: string;
    /** Minutes per unit; null disables the whole time block (games). */
    minsPerUnit?: number | null;
    /** Singular noun for the pacing caption: episode / chapter / page. */
    unitNoun?: string | null;
    paceOptions: readonly number[];
    paceDefault?: number;
    startHint: string;
    finishedAt?: string | null;
    totalTooltip?: string | null;
    accent: ProgressAccent;
    error: unknown;
    onStep: (delta: number) => void;
    onCounterChange?: (value: number) => void;
  }

  let {
    label,
    value,
    total,
    percent,
    unitShort,
    doneLabel,
    remainLabel,
    minsPerUnit = null,
    unitNoun = null,
    paceOptions,
    paceDefault = 1,
    startHint,
    finishedAt = null,
    totalTooltip = null,
    accent,
    error,
    onStep,
    onCounterChange,
  }: Props = $props();

  // Flat, category-specific accent. Literal class strings only: no gradients, no glow
  // shadows, no confetti — the deslop and muted-color checks guard this on purpose.
  const ACCENTS: Record<
    ProgressAccent,
    { text: string; stroke: string; fill: string; fillSoft: string; buttonFill: string; outline: string; chipActive: string; chipIdle: string; quiet: string }
  > = {
    indigo: {
      text: "text-[#8b7cf6]",
      stroke: "stroke-[#8b7cf6]",
      fill: "bg-[#8b7cf6]",
      fillSoft: "bg-[#8b7cf6]/35",
      buttonFill: "bg-[#8b7cf6] text-white hover:bg-[#7b6cea]",
      outline: "border border-[#8b7cf6]/50 text-[#8b7cf6] hover:bg-[#8b7cf6]/10",
      chipActive: "border-[#8b7cf6]/60 bg-[#8b7cf6]/15 text-[#8b7cf6]",
      chipIdle: "border-white/10 text-slate-400 hover:bg-white/5 hover:text-white",
      quiet: "border-white/10 text-slate-400 hover:bg-white/[0.06] hover:text-white",
    },
    amber: {
      text: "text-amber-500",
      stroke: "stroke-amber-500",
      fill: "bg-amber-500/90",
      fillSoft: "bg-amber-500/35",
      buttonFill: "bg-amber-500/90 text-black hover:bg-amber-500",
      outline: "border border-amber-500/50 text-amber-500 hover:bg-amber-500/10",
      chipActive: "border-amber-500/60 bg-amber-500/15 text-amber-500",
      chipIdle: "border-white/10 text-slate-400 hover:bg-white/5 hover:text-white",
      quiet: "border-white/10 text-slate-400 hover:bg-white/[0.06] hover:text-white",
    },
    teal: {
      text: "text-teal-500",
      stroke: "stroke-teal-500",
      fill: "bg-teal-500/90",
      fillSoft: "bg-teal-500/35",
      buttonFill: "bg-teal-500/90 text-black hover:bg-teal-500",
      outline: "border border-teal-500/50 text-teal-500 hover:bg-teal-500/10",
      chipActive: "border-teal-500/60 bg-teal-500/15 text-teal-500",
      chipIdle: "border-white/10 text-slate-400 hover:bg-white/5 hover:text-white",
      quiet: "border-white/10 text-slate-400 hover:bg-white/[0.06] hover:text-white",
    },
    theme: {
      text: "text-accent-soft",
      stroke: "stroke-[var(--color-accent)]",
      fill: "bg-accent",
      fillSoft: "bg-accent/35",
      buttonFill: "bg-accent text-white hover:bg-accent-hover",
      outline: "border border-accent/50 text-accent-soft hover:bg-accent/10",
      chipActive: "border-accent/60 bg-accent/15 text-accent-soft",
      chipIdle: "border-white/10 text-slate-400 hover:bg-white/5 hover:text-white",
      quiet: "border-white/10 text-slate-400 hover:bg-white/[0.06] hover:text-white",
    },
  };
  const a = $derived(ACCENTS[accent]);

  const RING_RADIUS = 48;
  const RING_C = 2 * Math.PI * RING_RADIUS;
  const SEGMENT_LIMIT = 36;
  const MILESTONES = [25, 50, 75];

  const pct = $derived(Math.min(100, Math.max(0, percent)));
  const isCompleted = $derived(total > 0 && value >= total);
  const isEmpty = $derived(value === 0 && !isCompleted);
  const segmented = $derived(total > 0 && total <= SEGMENT_LIMIT);
  const remainingUnits = $derived(Math.max(0, total - value));

  const watchedMinutes = $derived(
    minsPerUnit ? Math.round(value * minsPerUnit) : 0,
  );
  const totalMinutes = $derived(
    minsPerUnit && total > 0 ? Math.round(total * minsPerUnit) : 0,
  );
  const remainingMinutes = $derived(
    minsPerUnit ? Math.round(remainingUnits * minsPerUnit) : 0,
  );

  // The default pace is read once: the chip selection is user state, not a live derivation.
  let pace = $state(untrack(() => paceDefault));
  const daysAtPace = $derived(
    pace > 0 && remainingUnits > 0 ? Math.ceil(remainingUnits / pace) : null,
  );
  const finishEstimate = $derived.by(() => {
    if (daysAtPace === null) return null;
    const date = new Date(Date.now() + daysAtPace * 86_400_000);
    const label = new Intl.DateTimeFormat(i18n.current, {
      day: "numeric",
      month: "long",
    }).format(date);
    return i18n.t.progress.finishAt(label, daysAtPace);
  });

  const doneCaption = $derived(
    minsPerUnit
      ? `${doneLabel} ${formatNumber(watchedMinutes)} ${i18n.t.progress.minShort}`
      : `${doneLabel} ${formatNumber(value)} ${unitShort}`.trim(),
  );

  const unitDurationCaption = $derived.by(() => {
    if (!minsPerUnit || !unitNoun || total <= 0) return null;
    const mins = Number.isInteger(minsPerUnit)
      ? `${Math.round(minsPerUnit)} ${i18n.t.progress.minShort}`
      : `~${Math.round(minsPerUnit)} ${i18n.t.progress.minShort}`;
    return `${i18n.t.progress.unitDuration(unitNoun, mins)} · ${i18n.t.progress.totalDuration(formatDuration(totalMinutes))}`;
  });

  const finishedDateLabel = $derived.by(() => {
    if (!finishedAt) return null;
    const date = new Date(finishedAt);
    return Number.isNaN(date.getTime())
      ? null
      : new Intl.DateTimeFormat(i18n.current, { dateStyle: "medium" }).format(date);
  });

  function formatDuration(minutes: number): string {
    const hours = Math.floor(minutes / 60);
    const mins = Math.round(minutes % 60);
    if (hours > 0 && mins > 0) return i18n.t.progress.durationHM(hours, mins);
    if (hours > 0) return i18n.t.progress.durationH(hours);
    return i18n.t.progress.durationM(mins);
  }

  let isEditing = $state(false);
  let editValue = $state("");
  let isDragging = $state(false);
  let barElement: HTMLElement | null = $state(null);

  function focusOnMount(el: HTMLElement) {
    el.focus();
    if (el instanceof HTMLInputElement) el.select();
  }

  function applyValue(nextVal: number) {
    const clamped = Math.max(0, total > 0 ? Math.min(nextVal, total) : nextVal);
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
    if (!barElement || total <= 0) return value;
    const rect = barElement.getBoundingClientRect();
    if (rect.width <= 0) return value;
    const offsetX = Math.max(0, Math.min(clientX - rect.left, rect.width));
    const ratio = offsetX / rect.width;
    return Math.round(ratio * total);
  }

  function handlePointerDown(e: PointerEvent) {
    if (total <= 0) return;
    isDragging = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    applyValue(calculateValueFromPointer(e.clientX));
  }

  function handlePointerMove(e: PointerEvent) {
    if (!isDragging || total <= 0) return;
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
  class={`space-y-4 rounded-xl border bg-[var(--color-panel-line)] p-5 shadow-sm ${
    isCompleted ? "border-emerald-400/30" : "border-white/[0.06]"
  }`}
>
  <!-- 1. Header zone: SVG ring + big counter + control hierarchy -->
  <div class="flex items-center gap-4">
    {#if total > 0}
      <div class="relative size-[104px] shrink-0">
        <svg viewBox="0 0 104 104" class="size-full -rotate-90" aria-hidden="true">
          <circle
            cx="52"
            cy="52"
            r={RING_RADIUS}
            fill="none"
            stroke-width="8"
            class="stroke-white/[0.07]"
          />
          <circle
            cx="52"
            cy="52"
            r={RING_RADIUS}
            fill="none"
            stroke-width="8"
            stroke-linecap="round"
            class={a.stroke}
            stroke-dasharray={RING_C}
            stroke-dashoffset={RING_C * (1 - pct / 100)}
            style="transition: stroke-dashoffset 300ms ease;"
          />
        </svg>
        <span
          class="absolute inset-0 grid place-items-center text-lg font-bold text-white tabular-nums"
        >
          {Math.round(pct)}%
        </span>
      </div>
    {/if}

    <div class="min-w-0 flex-1 space-y-1.5">
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs font-bold tracking-wider text-slate-300 uppercase">{label}</span>
        {#if isCompleted}
          <span
            class="inline-flex items-center gap-1 rounded-full border border-emerald-400/30 bg-emerald-400/10 px-2 py-0.5 text-[11px] font-bold text-emerald-300"
          >
            <Check size={11} stroke-width={3} aria-hidden="true" />
            {i18n.t.progress.completedBadge}
          </span>
        {/if}
      </div>
      <div class="flex flex-wrap items-baseline gap-x-2">
        {#if isEditing}
          <input
            type="number"
            min="0"
            max={total > 0 ? total : undefined}
            class="focus:border-accent h-10 w-24 rounded-lg border border-white/10 bg-black/60 px-2 text-center text-[28px] font-extrabold text-white tabular-nums outline-none"
            bind:value={editValue}
            onblur={commitEditing}
            onkeydown={handleKeydown}
            use:focusOnMount
          />
        {:else}
          <button
            type="button"
            class="cursor-pointer text-[38px] leading-none font-extrabold text-white tabular-nums transition hover:opacity-80"
            onclick={startEditing}
            title={i18n.t.progress.manualInputTitle}
          >
            {#key value}<span class="counter-pop inline-block">{formatNumber(value)}</span>{/key}
          </button>
        {/if}
        {#if total > 0}
          <span
            class="text-muted text-[17px] font-semibold tabular-nums"
            title={totalTooltip ?? undefined}
          >
            / {formatNumber(total)} {unitShort}
          </span>
        {/if}
      </div>
    </div>

    <!-- Control hierarchy: quiet −, filled +1, outlined +5; an empty card swaps the
         triad for one prominent Start (which performs +1). -->
    <div class="flex shrink-0 items-center gap-1.5">
      {#if isCompleted}
        <button
          type="button"
          class={`tap grid size-8 cursor-pointer place-items-center rounded-lg border transition disabled:cursor-not-allowed disabled:opacity-40 ${a.quiet}`}
          aria-label={i18n.t.card.decrement}
          disabled={value <= 0}
          onclick={() => onStep(-1)}
        >
          <Minus size={15} aria-hidden="true" />
        </button>
      {:else if isEmpty}
        <button
          type="button"
          class={`tap flex h-9 cursor-pointer items-center gap-1.5 rounded-lg px-4 text-sm font-bold transition disabled:cursor-not-allowed disabled:opacity-40 ${a.buttonFill}`}
          onclick={() => onStep(1)}
        >
          {i18n.t.progress.startButton}
        </button>
      {:else}
        <button
          type="button"
          class={`tap grid size-8 cursor-pointer place-items-center rounded-lg border transition disabled:cursor-not-allowed disabled:opacity-40 ${a.quiet}`}
          aria-label={i18n.t.card.decrement}
          disabled={value <= 0}
          onclick={() => onStep(-1)}
        >
          <Minus size={15} aria-hidden="true" />
        </button>
        <button
          type="button"
          class={`tap flex h-8 cursor-pointer items-center justify-center rounded-lg px-3 text-xs font-bold transition disabled:cursor-not-allowed disabled:opacity-40 ${a.buttonFill}`}
          aria-label="+1"
          disabled={total > 0 && value >= total}
          onclick={() => onStep(1)}
        >
          +1
        </button>
        {#if total === 0 || total - value >= 5}
          <button
            type="button"
            class={`tap flex h-8 cursor-pointer items-center justify-center rounded-lg border px-2.5 text-xs font-bold transition disabled:cursor-not-allowed disabled:opacity-40 ${a.outline}`}
            aria-label="+5"
            disabled={total > 0 && value >= total}
            onclick={() => onStep(5)}
          >
            +5
          </button>
        {/if}
      {/if}
    </div>
  </div>

  {#if error}
    <p class="text-xs text-rose-300" role="alert">
      {errorMessage(error)}
    </p>
  {/if}

  <!-- 2. Progress track: segmented for small totals, continuous for long ones.
           Milestone dots ride below the track at 25 / 50 / 75 / 100%. -->
  {#if total > 0}
    <div
      bind:this={barElement}
      role="slider"
      tabindex="0"
      aria-label={label}
      aria-valuenow={value}
      aria-valuemin="0"
      aria-valuemax={total}
      class="cursor-pointer touch-none select-none"
      onpointerdown={handlePointerDown}
      onpointermove={handlePointerMove}
      onpointerup={handlePointerUp}
      onpointercancel={handlePointerUp}
    >
      {#if segmented}
        <div class="flex h-2.5 w-full gap-[3px]">
          {#each Array(total) as _, i (i)}
            <div
              class={`h-full flex-1 rounded-[3px] transition-colors ${
                i < value ? a.fill : i === value ? `${a.fillSoft} animate-pulse` : "bg-white/[0.08]"
              }`}
            ></div>
          {/each}
        </div>
      {:else}
        <div class="h-2.5 w-full overflow-hidden rounded-full bg-white/[0.08]">
          <div
            class={`h-full rounded-full transition-[width] duration-150 ease-out ${a.fill}`}
            style="width: {pct}%"
          ></div>
        </div>
      {/if}
      <div class="relative mt-1.5 h-1.5">
        {#each MILESTONES as m (m)}
          <span
            class={`absolute top-0 size-1.5 -translate-x-1/2 rounded-full ${
              pct >= m ? "bg-white/40" : "bg-white/15"
            }`}
            style={`left: ${m}%`}
          ></span>
        {/each}
        <span
          class={`absolute top-0 right-0 size-1.5 rounded-full ${
            pct >= 100 ? "bg-white/40" : "bg-white/15"
          }`}
        ></span>
      </div>
    </div>

    <div class="flex items-center justify-between gap-3 text-[11px]">
      <span class="text-muted">{doneCaption}</span>
      {#if !isCompleted}
        <span class="text-muted tabular-nums">
          {i18n.t.progress.remainingOf(remainingUnits, total)}
        </span>
      {/if}
    </div>
  {/if}

  <!-- 3. Bottom zone: inviting start, single time accent block with pace calculator,
           or the completed summary. -->
  {#if isEmpty}
    <p class="text-xs text-slate-300">{startHint}</p>
  {:else if isCompleted}
    {#if minsPerUnit && total > 0}
      <div
        class="flex items-center justify-between gap-3 rounded-xl border border-emerald-400/20 bg-emerald-400/[0.06] px-3.5 py-3"
      >
        <div class="min-w-0">
          <p class="text-[11px] font-semibold tracking-wider text-emerald-300/80 uppercase">
            {i18n.t.progress.totalTimeLabel}
          </p>
          <p class="text-xl font-bold text-white tabular-nums">
            {formatDuration(totalMinutes)}
          </p>
        </div>
        {#if finishedDateLabel}
          <div class="shrink-0 text-right">
            <p class="text-muted text-[11px]">{i18n.t.progress.finishedOn}</p>
            <p class="text-xs font-medium text-slate-200">{finishedDateLabel}</p>
          </div>
        {/if}
      </div>
    {/if}
  {:else if minsPerUnit && total > 0}
    <div class="rounded-xl border border-white/[0.06] bg-black/15 px-3.5 py-3">
      <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span class="text-muted text-[11px] font-semibold tracking-wider uppercase">
          {i18n.t.progress.remainingTimeLabel}
        </span>
        <span class="text-[26px] leading-none font-bold text-white tabular-nums">
          {formatDuration(remainingMinutes)}
        </span>
        {#if minsPerUnit && remainingUnits > 0}
          <span class="text-muted text-xs tabular-nums">
            {remainLabel}
            {formatNumber(remainingUnits)}
            {unitShort}
          </span>
        {/if}
      </div>
      {#if unitDurationCaption}
        <p class="text-muted mt-1.5 text-[11px]">{unitDurationCaption}</p>
      {/if}
    </div>

    {#if paceOptions.length > 0 && remainingUnits > 0}
      <div class="flex flex-wrap items-center gap-1.5">
        <span class="text-muted text-[11px]">{i18n.t.progress.paceLabel}:</span>
        {#each paceOptions as p (p)}
          <button
            type="button"
            class={`tap flex h-6 min-w-7 cursor-pointer items-center justify-center rounded-md border px-1.5 text-xs font-bold tabular-nums transition ${
              pace === p ? a.chipActive : a.chipIdle
            }`}
            aria-pressed={pace === p}
            onclick={() => (pace = p)}
          >
            {p}
          </button>
        {/each}
        <span class="text-muted text-[11px]">{i18n.t.progress.pacePerDay(unitShort)}</span>
        {#if finishEstimate}
          <span class="text-xs text-slate-300">
            → {finishEstimate}
          </span>
        {/if}
      </div>
    {/if}
  {/if}
</section>

<style>
  /* Soft value pop on change: a light scale roll without re-flowing the layout. */
  .counter-pop {
    animation: counter-pop 180ms ease-out;
  }

  @keyframes counter-pop {
    0% {
      transform: scale(1.12);
    }
    100% {
      transform: scale(1);
    }
  }
</style>
