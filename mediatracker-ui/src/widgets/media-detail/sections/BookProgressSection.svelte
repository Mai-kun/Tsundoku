<script lang="ts">
    import { i18n } from "$shared/i18n/index.svelte";
    import { BookOpen, Clock, Minus, Plus } from "$shared/ui/Icons.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";
    import { errorMessage } from "$shared/api/api";
    import type { ProgressInfo } from "../detailTypes";

    interface Props {
        totalPages: number;
        currentPage: number;
        progress: ProgressInfo;
        value: number;
        percent: number;
        error: unknown;
        onStep: (delta: number) => void;
    }

    let {
        totalPages,
        currentPage,
        progress,
        value,
        percent,
        error,
        onStep,
    }: Props = $props();

    // ponytail: 1.5 min/page is a common reading speed heuristic
    const MINS_PER_PAGE = 1.5;
    const DAILY_PACE = 20;

    const totalMinutes = $derived(Math.round(totalPages * MINS_PER_PAGE));
    const totalHours = $derived((totalMinutes / 60).toFixed(1));
    const remainingPages = $derived(Math.max(0, totalPages - value));
    const remainingMinutes = $derived(Math.round(remainingPages * MINS_PER_PAGE));
    const remainingHours = $derived((remainingMinutes / 60).toFixed(1));
    const daysAtPace = $derived(Math.ceil(remainingPages / DAILY_PACE));

    const isRu = $derived(i18n.current === "ru");
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
                {totalPages > 0
                    ? `${formatNumber(value)} / ${formatNumber(totalPages)}`
                    : formatNumber(value)}
                {isRu ? "стр." : "pages"}
            </span>
            {#if totalPages > 0}
                <span class="rounded-full bg-accent-soft/10 px-2 py-0.5 text-[11px] font-semibold text-accent-soft">
                    {Math.round(percent)}%
                </span>
            {/if}
        </div>
    </div>

    <!-- Степпер прочитанных страниц -->
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
            disabled={totalPages > 0 && value >= totalPages}
            onclick={() => onStep(1)}
        >
            <Plus size={15} aria-hidden="true" />
        </button>
    </div>

    <!-- Стилизованная полоса прогресса -->
    {#if totalPages > 0}
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
    {#if totalPages > 0}
        <div class="grid grid-cols-2 gap-2 text-xs">
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2">
                <span class="text-muted">{isRu ? "Ориентировочно на книгу" : "Estimated total time"}</span>
                <span class="font-semibold text-white">~{totalHours} {isRu ? "ч." : "h"}</span>
            </div>
            <div class="flex flex-col gap-0.5 rounded-lg border border-white/[0.06] bg-black/15 px-3 py-2">
                <span class="text-muted">{isRu ? "Осталось читать" : "Remaining reading time"}</span>
                <span class="font-semibold text-white">~{remainingHours} {isRu ? "ч." : "h"}</span>
            </div>
        </div>

        {#if remainingPages > 0}
            <div class="flex items-center gap-2 text-xs text-muted">
                <Clock size={13} class="shrink-0 text-accent-soft" />
                <span>
                    {isRu
                        ? `При темпе ${DAILY_PACE} стр./день чтение займет ~${daysAtPace} дн.`
                        : `At ${DAILY_PACE} pages/day reading will take ~${daysAtPace} days`}
                </span>
            </div>
        {:else}
            <div class="text-xs font-semibold text-emerald-400">
                {isRu ? "✓ Книга полностью прочитана!" : "✓ Book completed!"}
            </div>
        {/if}
    {/if}
</section>
