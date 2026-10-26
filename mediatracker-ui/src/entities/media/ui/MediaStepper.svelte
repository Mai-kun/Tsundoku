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

  let { text, onStep, decrementDisabled = false, incrementDisabled = false }: Props = $props();
</script>

<div class="bg-canvas flex h-8 items-center rounded-md">
  <button
    type="button"
    class="tap text-muted hover:bg-panel hover:text-ink grid h-full w-8 place-items-center rounded-l-md transition disabled:opacity-40"
    aria-label={i18n.t.card.decrement}
    disabled={decrementDisabled}
    onclick={(event) => {
      event.stopPropagation();
      onStep(-1);
    }}><Minus size={14} aria-hidden="true" /></button
  >
  <span class="text-ink flex-1 text-center text-xs font-semibold tabular-nums">{text}</span>
  <button
    type="button"
    class="tap text-muted hover:bg-panel hover:text-ink grid h-full w-8 place-items-center rounded-r-md transition disabled:opacity-40"
    aria-label={i18n.t.card.increment}
    disabled={incrementDisabled}
    onclick={(event) => {
      event.stopPropagation();
      onStep(1);
    }}><Plus size={14} aria-hidden="true" /></button
  >
</div>
