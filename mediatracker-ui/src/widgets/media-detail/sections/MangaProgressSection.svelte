<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import { BookOpen, Clock, Layers, Minus, Plus } from "$shared/ui/Icons.svelte";
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

    const hasVolumes = $derived((media.totalVolumes ?? 0) > 0);
    const volumePercent = $derived(
        hasVolumes ? Math.round(((media.currentVolume ?? 0) / (media.totalVolumes || 1)) * 100) : 0
    );
</script>

<section class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
    <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
            <BookOpen size={16} class="shrink-0 text-accent-soft" />
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {isRu ? "Чтение и прогресс" : "Reading & Progress"}
            </h2>
        </div>
        <div class="flex items-center gap-2">
            <span class="text-xs font-bold tabular-nums text-slate-300">
                {effectiveTotal > 0
                    ? `${formatNumber(value)} / ${formatNumber(effectiveTotal)}`
                    : formatNumber(value)}
                {isRu ? "гл." : "ch."}
            </span>
            {#if effectiveTotal > 0}
                <span class="rounded-full bg-accent-soft/10 px-2 py-0.5 text-[11px] font-semibold text-accent-soft">
                    {Math.round(percent)}%
                </span>
            {/if}
        </div>
    </div>

    <!-- Степпер прочитанных глав -->
    <div class="flex h-10 items-center rounded-lg bg-[var(--color-field)] border border-white/[0.06]">
        <button
            type="button"
            class="grid h-full w-10 place-items-center rounded-l-lg text-[var(--color-muted)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-40 cursor-pointer"
            aria-label={i18n.t.card.decrement}
            disabled={value <= 0}
            onclick={() => onStep(-1)}
        >
            <Minus size={15} aria-hidden="true" />
        </button>
        <span class="flex-1 text-center text-sm font-semibold tabular-nums text-white">
            {formatNumber(value)}
        </span>
        <button
            type="button"
            class="grid h-full w-10 place-items-center rounded-r-lg text-[var(--color-muted)] transition hover:bg-[var(--color-panel-raised)] hover:text-white cursor-pointer"
            aria-label={i18n.t.card.increment}
            disabled={effectiveTotal > 0 && value >= effectiveTotal}
            onclick={() => onStep(1)}
        >
            <Plus size={15} aria-hidden="true" />
        </button>
    </div>

    <!-- Стилизованная полоса прогресса -->
    {#if effectiveTotal > 0}
        <div class="space-y-1">
            <div class="h-2 w-full overflow-hidden rounded-full bg-[var(--color-field)] border border-white/[0.04]">
                <div
                    class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#7f6ff0] transition-all duration-200"
                    style={`width: ${Math.min(100, Math.max(0, percent))}%`}
                ></div>
            </div>
        </div>
    {/if}

    {#if error}
        <p class="text-xs text-rose-300" role="alert">
            {errorMessage(error)}
        </p>
    {/if}

    <!-- Расчет времени и темп -->
    {#if effectiveTotal > 0}
        <div class="grid grid-cols-2 gap-2 text-xs">
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

    <!-- Прогресс по томам (если ведется учет) -->
    {#if hasVolumes}
        <div class="space-y-1.5 pt-2 border-t border-white/[0.06]">
            <div class="flex items-center justify-between text-xs">
                <div class="flex items-center gap-1.5 text-muted">
                    <Layers size={14} class="shrink-0 text-accent-soft" />
                    <span>{isRu ? "Прогресс по томам" : "Volume progress"}</span>
                </div>
                <div class="flex items-center gap-2">
                    <span class="font-medium tabular-nums text-slate-300">
                        {formatNumber(media.currentVolume ?? 0)} / {formatNumber(media.totalVolumes ?? 0)}
                        {isRu ? "том." : "vol."}
                    </span>
                    <span class="rounded-full bg-accent-soft/10 px-1.5 py-0.5 text-[10px] font-semibold text-accent-soft">
                        {volumePercent}%
                    </span>
                </div>
            </div>
            <div class="h-1.5 w-full overflow-hidden rounded-full bg-[var(--color-field)] border border-white/[0.04]">
                <div
                    class="h-full rounded-full bg-accent-soft/80 transition-all duration-200"
                    style={`width: ${Math.min(100, Math.max(0, volumePercent))}%`}
                ></div>
            </div>
        </div>
    {/if}
</section>
