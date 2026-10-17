<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { Tv, Clock, Minus, Plus } from "$shared/ui/Icons.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";
    import { errorMessage } from "$shared/api/api";
    import type { ProgressInfo } from "../detailTypes";
    import type { MediaDetail, TvShowMedia } from "$shared/types";

    interface Props {
        media: MediaDetail;
        totalEpisodes: number;
        watchedEpisodes: number;
        progress: ProgressInfo;
        value: number;
        percent: number;
        error: unknown;
        onStep: (delta: number) => void;
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
    }: Props = $props();

    const tvMedia = $derived(media as unknown as TvShowMedia);
    const duration = $derived(tvMedia.episodeDurationMinutes || tvMedia.durationMinutes || 24);
    const DAILY_PACE = 2;

    const effectiveTotal = $derived(totalEpisodes > 0 ? totalEpisodes : (progress.total ?? 0));
    const effectiveWatched = $derived(value);
    const remainingEpisodes = $derived(Math.max(0, effectiveTotal - effectiveWatched));

    const totalHours = $derived(((effectiveTotal * duration) / 60).toFixed(1));
    const watchedHours = $derived(((effectiveWatched * duration) / 60).toFixed(1));
    const remainingHours = $derived(((remainingEpisodes * duration) / 60).toFixed(1));
    const daysAtPace = $derived(Math.ceil(remainingEpisodes / DAILY_PACE));

    const isRu = $derived(i18n.current === "ru");
    const isAnime = $derived(Boolean(tvMedia.isAnime));
</script>

<section class="space-y-4 rounded-xl border border-white/[0.06] bg-[var(--color-panel-line)] p-5 shadow-sm">
    <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
            <Tv size={16} class="shrink-0 text-accent-soft" />
            <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {isRu ? (isAnime ? "Просмотр аниме" : "Просмотр сериала") : (isAnime ? "Anime Watching" : "Series Watching")}
            </h2>
        </div>
        <div class="flex items-center gap-2">
            <span class="text-xs font-bold tabular-nums text-slate-300">
                {effectiveTotal > 0
                    ? `${formatNumber(value)} / ${formatNumber(effectiveTotal)}`
                    : formatNumber(value)}
                {isRu ? "эп." : "ep."}
            </span>
            {#if effectiveTotal > 0}
                <span class="rounded-full bg-accent-soft/10 px-2 py-0.5 text-[11px] font-semibold text-accent-soft">
                    {Math.round(percent)}%
                </span>
            {/if}
        </div>
    </div>

    <!-- Степпер просмотренных серий -->
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

    <!-- Полоса прогресса -->
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

    <!-- Блок аналитики времени просмотра -->
    {#if effectiveTotal > 0}
        <div class="grid grid-cols-3 gap-2 text-xs">
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2">
                <span class="text-muted truncate">{isRu ? "Всего времени" : "Total time"}</span>
                <span class="font-semibold text-white">~{totalHours} {isRu ? "ч." : "h"}</span>
            </div>
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2">
                <span class="text-muted truncate">{isRu ? "Просмотрено" : "Watched"}</span>
                <span class="font-semibold text-white">~{watchedHours} {isRu ? "ч." : "h"}</span>
            </div>
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-2.5 py-2">
                <span class="text-muted truncate">{isRu ? "Осталось смотреть" : "Remaining"}</span>
                <span class="font-semibold text-white">~{remainingHours} {isRu ? "ч." : "h"}</span>
            </div>
        </div>

        <div class="flex items-center justify-between text-[11px] text-muted">
            <span>
                {isRu ? "Хронометраж серии:" : "Episode duration:"} <strong class="text-slate-300 font-medium">~{duration} {isRu ? "мин." : "min"}</strong>
            </span>
        </div>

        {#if remainingEpisodes > 0}
            <div class="flex items-center gap-2 text-xs text-muted">
                <Clock size={13} class="shrink-0 text-accent-soft" />
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
