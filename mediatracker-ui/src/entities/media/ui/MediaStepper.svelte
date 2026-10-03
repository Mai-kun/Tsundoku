<script lang="ts">
    import { Minus, Plus } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";

    interface Props {
        /** Already formatted for the current locale. */
        text: string;
        onStep: (delta: number) => void;
        decrementDisabled?: boolean;
        incrementDisabled?: boolean;
    }

    let { text, onStep, decrementDisabled = false, incrementDisabled = false }: Props =
        $props();
</script>

<div class="flex h-8 items-center rounded-md bg-canvas">
    <button
        type="button"
        class="tap grid h-full w-8 place-items-center rounded-l-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
        aria-label={i18n.t.card.decrement}
        disabled={decrementDisabled}
        onclick={(event) => {
            event.stopPropagation();
            onStep(-1);
        }}><Minus size={14} aria-hidden="true" /></button
    >
    <span class="flex-1 text-center text-xs font-semibold tabular-nums text-ink"
        >{text}</span
    >
    <button
        type="button"
        class="tap grid h-full w-8 place-items-center rounded-r-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
        aria-label={i18n.t.card.increment}
        disabled={incrementDisabled}
        onclick={(event) => {
            event.stopPropagation();
            onStep(1);
        }}><Plus size={14} aria-hidden="true" /></button
    >
</div>