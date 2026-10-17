<script lang="ts">
    import { Minus, Plus } from "$shared/ui/Icons.svelte";
    import { errorMessage } from "$shared/api/api";
    import { i18n } from "$shared/i18n/index.svelte";
    import { formatNumber } from "$entities/media/model/mediaLabels";
    import type { ProgressInfo } from "./detailTypes";

    interface Props {
        progress: ProgressInfo;
        value: number;
        percent: number;
        error: unknown;
        onStep: (delta: number) => void;
        onCounterChange?: (value: number) => void;
    }

    let { progress, value, percent, error, onStep, onCounterChange }: Props = $props();

    const isRu = $derived(i18n.current === "ru");
    const total = $derived(progress.total ?? 0);

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
    class="flex flex-col justify-center space-y-3.5 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
>
    <!-- Верхняя строка: заголовок, крупный счетчик с inline-input и капсула кнопок -->
    <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5 min-w-0 flex-wrap">
            <span class="text-xs font-bold uppercase tracking-wider text-slate-300">
                {progress.label}
            </span>
            <div class="flex items-center gap-1.5">
                {#if isEditing}
                    <input
                        type="number"
                        min="0"
                        max={total > 0 ? total : undefined}
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
                {#if total > 0}
                    <span class="text-xs font-bold text-muted tabular-nums">
                        / {formatNumber(total)}
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
                disabled={total > 0 && value >= total}
                onclick={() => onStep(1)}
            >
                +1
            </button>
            {#if total === 0 || total - value >= 5}
                <button
                    type="button"
                    class="h-8 px-2 rounded-lg bg-[var(--color-field)] border border-white/10 hover:bg-white/10 text-slate-300 hover:text-white font-bold text-xs flex items-center justify-center disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer transition"
                    aria-label="+5"
                    disabled={total > 0 && value >= total}
                    onclick={() => onStep(5)}
                >
                    +5
                </button>
            {/if}
        </div>
    </div>

    <!-- Интерактивная шкала-прогрессбар -->
    {#if total > 0}
        <div
            bind:this={barElement}
            role="slider"
            tabindex="0"
            aria-label={progress.label}
            aria-valuenow={value}
            aria-valuemin="0"
            aria-valuemax={total}
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
</section>
