<script lang="ts">
    import Minus from "lucide-svelte/icons/minus";
    import Plus from "lucide-svelte/icons/plus";
    import { errorMessage } from "$lib/api";
    import { i18n } from "$lib/i18n/index.svelte";
    import { formatNumber } from "$lib/components/media/mediaLabels";
    import type { ProgressInfo } from "./detailTypes";

    interface Props {
        progress: ProgressInfo;
        value: number;
        percent: number;
        error: unknown;
        onStep: (delta: number) => void;
    }

    let { progress, value, percent, error, onStep }: Props = $props();
</script>

<section
    class="space-y-3 rounded-xl bg-[var(--color-panel-line)] p-5 shadow-sm border border-white/[0.06]"
>
    <div class="flex items-center justify-between gap-3">
        <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
            {progress.label}
        </h2>
        <span class="text-sm font-semibold tabular-nums text-white">
            {progress.total !== null
                ? `${formatNumber(value)} / ${formatNumber(progress.total)}`
                : formatNumber(value)}
        </span>
    </div>
    <div class="flex h-10 items-center rounded-lg bg-[var(--color-field)]">
        <button
            type="button"
            class="grid h-full w-10 place-items-center rounded-l-lg text-[var(--color-muted)] transition hover:bg-[var(--color-panel-raised)] hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
            aria-label={i18n.t.card.decrement}
            disabled={value <= 0}
            onclick={() => onStep(-1)}
        >
            <Minus size={15} aria-hidden="true" />
        </button>
        <span
            class="flex-1 text-center text-sm font-semibold tabular-nums text-white"
            >{formatNumber(value)}</span
        >
        <button
            type="button"
            class="grid h-full w-10 place-items-center rounded-r-lg text-[var(--color-muted)] transition hover:bg-[var(--color-panel-raised)] hover:text-white"
            aria-label={i18n.t.card.increment}
            onclick={() => onStep(1)}
        >
            <Plus size={15} aria-hidden="true" />
        </button>
    </div>
    {#if progress.total !== null && progress.total > 0}
        <div
            class="h-1.5 w-full max-w-2xl overflow-hidden rounded-full bg-[var(--color-field)]"
        >
            <div
                class="h-full rounded-full bg-[var(--color-accent)] transition-[width] duration-200"
                style={`width: ${percent}%`}
            ></div>
        </div>
    {/if}
    {#if error}
        <p class="text-xs text-rose-300" role="alert">
            {errorMessage(error)}
        </p>
    {/if}
</section>