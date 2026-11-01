<script lang="ts">
  import { Minus, Plus } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { errorMessage } from "$shared/api/api";

  interface Props {
    text: string;
    onStep: (delta: number) => void;
    decrementDisabled?: boolean;
    incrementDisabled?: boolean;
    /** Progress request failure, surfaced under the stepper. */
    error?: unknown;
  }

  let {
    text,
    onStep,
    decrementDisabled = false,
    incrementDisabled = false,
    error = null,
  }: Props = $props();

  // A stepper button that keeps focus after a click holds the card's
  // focus-within state forever, so the info layer never comes back once the
  // pointer leaves. Release the focus as part of the click itself.
  function step(event: MouseEvent, delta: number) {
    event.stopPropagation();
    (event.currentTarget as HTMLElement).blur();
    onStep(delta);
  }
</script>

<div class="flex w-full items-center gap-1.5">
  <button
    type="button"
    class="tap bg-field text-muted hover:text-ink flex h-9 w-9 shrink-0 items-center justify-center rounded-lg transition hover:bg-white/10 disabled:opacity-40"
    aria-label={i18n.t.card.decrement}
    disabled={decrementDisabled}
    onclick={(event) => step(event, -1)}><Minus size={16} aria-hidden="true" /></button
  >
  <span class="flex-1 text-center text-xs font-bold text-white tabular-nums">{text}</span>
  <button
    type="button"
    class="tap bg-field text-muted hover:text-ink flex h-9 w-9 shrink-0 items-center justify-center rounded-lg transition hover:bg-white/10 disabled:opacity-40"
    aria-label={i18n.t.card.increment}
    disabled={incrementDisabled}
    onclick={(event) => step(event, 1)}><Plus size={16} aria-hidden="true" /></button
  >
</div>

{#if error}
  <p class="text-xs leading-4 text-rose-300" role="alert">
    {errorMessage(error)}
  </p>
{/if}
