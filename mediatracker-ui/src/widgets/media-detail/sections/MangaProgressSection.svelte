<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import { Clock, Minus, Plus } from "$shared/ui/Icons.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";
    import { errorMessage } from "$shared/api/api";
    import type { ProgressInfo } from "../detailTypes";
    import type { MangaDetail } from "$shared/types";

    interface Props {
        media: MangaDetail;
        totalChapters: number;
        currentChapter: number;
        progress: ProgressInfo;
        value: number;
        percent: number;
        error: unknown;
        onStep: (delta: number) => void;
        onCounterChange?: (value: number) => void;
    }

    let {
        media,
        totalChapters,
        currentChapter,
        progress,
        value,
        percent,
        error,
        onStep,
        onCounterChange,
    }: Props = $props();

    const minsPerChapter = $derived(uiSettings.mangaChapterMinutes || 6.0);
    const DAILY_PACE = 5;

    const effectiveTotal = $derived(totalChapters > 0 ? totalChapters : (progress.total ?? 0));
    const totalMinutes = $derived(Math.round(effectiveTotal * minsPerChapter));
    const totalHours = $derived((totalMinutes / 60).toFixed(1));
    const remainingChapters = $derived(Math.max(0, effectiveTotal - value));
    const remainingMinutes = $derived(Math.round(remainingChapters * minsPerChapter));
    const remainingHours = $derived((remainingMinutes / 60).toFixed(1));
    const daysAtPace = $derived(Math.ceil(remainingChapters / DAILY_PACE));

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

<section class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
    <!-- 1. Верхняя строка: ГЛАВЫ, счетчик и капсула кнопок -->
    <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5 min-w-0 flex-wrap">
            <span class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {isRu ? "ГЛАВЫ" : "CHAPTERS"}
            </span>
            <div class="flex items-center gap-1.5">
                {#if isEditing}
                    <input
                        type="number"
                        min="0"
                        max={effectiveTotal > 0 ? effectiveTotal : undefined}
                        class="h-7 w-16 rounded-lg border border-accent bg-black/60 px-1 text-center text-lg font-black text-white outline-none ring-0 tabular-nums focus:border-accent"
                        bind:value={editValue}
                        onblur={commitEditing}
                        onkeydown={handleKeydown}
                        use:focusOnMount
                    />
                {:else}
                    <button
                        type="button"
                        class="cursor-pointer text-xl font-black text-white hover:text-accent-soft tabular-nums transition"
                        onclick={startEditing}
                        title={isRu ? "Нажмите для ручного ввода" : "Click to enter number"}
                    >
                        {formatNumber(value)}
                    </button>
                {/if}
                {#if effectiveTotal > 0}
                    <span class="text-xs font-bold text-muted tabular-nums">
                        / {formatNumber(effectiveTotal)}
                    </span>
                    <span class="rounded-full bg-accent-soft/10 px-2 py-0.5 text-xs font-bold text-accent-soft tabular-nums">
                        {Math.round(percent)}%
                    </span>
                {/if}
            </div>
        </div>

        <!-- Компактная сгруппированная капсула кнопок -->
        <div class="flex items-center gap-1.5 shrink-0">
            <button
                type="button"
                class="h-8 w-8 rounded-lg bg-[var(--color-field)] border border-white/10 hover:bg-white/10 grid place-items-center text-slate-300 hover:text-white disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer transition"
                aria-label={i18n.t.card.decrement}
                disabled={value <= 0}
                onclick={() => onStep(-1)}
            >
                <Minus size={15} aria-hidden="true" />
            </button>
            <button
                type="button"
                class="h-8 px-2.5 rounded-lg bg-accent/20 border border-accent/40 text-accent-soft hover:bg-accent hover:text-white font-bold text-xs flex items-center justify-center disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer transition"
                aria-label="+1"
                disabled={effectiveTotal > 0 && value >= effectiveTotal}
                onclick={() => onStep(1)}
            >
                +1
            </button>
            {#if effectiveTotal === 0 || effectiveTotal - value >= 5}
                <button
                    type="button"
                    class="h-8 px-2 rounded-lg bg-[var(--color-field)] border border-white/10 hover:bg-white/10 text-slate-300 hover:text-white font-bold text-xs flex items-center justify-center disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer transition"
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
            aria-label={isRu ? "Прогресс чтения глав" : "Chapter progress"}
            aria-valuenow={value}
            aria-valuemin="0"
            aria-valuemax={effectiveTotal}
            class="relative h-2.5 w-full cursor-pointer overflow-hidden rounded-full bg-[var(--color-field)] border border-white/[0.06] select-none touch-none shadow-inner"
            onpointerdown={handlePointerDown}
            onpointermove={handlePointerMove}
            onpointerup={handlePointerUp}
            onpointercancel={handlePointerUp}
        >
            <div
                class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#818cf8] shadow-[0_0_8px_rgba(129,140,248,0.4)] transition-all duration-150 ease-out"
                style="width: {Math.min(100, Math.max(0, percent))}%"
            ></div>
        </div>
    {/if}

    {#if error}
        <p class="text-xs text-rose-300" role="alert">
            {errorMessage(error)}
        </p>
    {/if}

    <!-- 3. Расчет времени и темп -->
    {#if effectiveTotal > 0}
        <div class="grid grid-cols-2 gap-2 text-xs pt-1">
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2">
                <span class="text-muted">{isRu ? "Ориентировочно на мангу" : "Estimated total time"}</span>
                <span class="font-semibold text-white">~{totalHours} {isRu ? "ч." : "h"}</span>
            </div>
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2">
                <span class="text-muted">{isRu ? "Осталось читать" : "Remaining reading time"}</span>
                <span class="font-semibold text-white">~{remainingHours} {isRu ? "ч." : "h"}</span>
            </div>
        </div>

        {#if remainingChapters > 0}
            <div class="flex items-center gap-2 text-xs text-muted">
                <Clock size={13} class="shrink-0 text-accent-soft" />
                <span>
                    {isRu
                        ? `При темпе ${DAILY_PACE} гл./день чтение займет ~${daysAtPace} дн.`
                        : `At ${DAILY_PACE} ch./day reading will take ~${daysAtPace} days`}
                </span>
            </div>
        {:else}
            <div class="text-xs font-semibold text-emerald-400">
                {isRu ? "✓ Манга полностью прочитана!" : "✓ Manga completed!"}
            </div>
        {/if}
    {/if}
</section>
