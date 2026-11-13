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
  <!-- Graphite glass: sits on the card's dark overlay without the white glare. -->
  <button
    type="button"
    class="tap flex h-7 w-7 shrink-0 items-center justify-center rounded-md border border-white/10 bg-[#1a202c]/90 text-zinc-300 shadow-sm transition-colors select-none hover:border-white/20 hover:bg-[#252d3d] hover:text-white active:bg-[#2d374a] disabled:opacity-40"
    aria-label={i18n.t.card.decrement}
    disabled={decrementDisabled}
    onclick={(event) => step(event, -1)}><Minus size={14} aria-hidden="true" /></button
  >
  <span
    class="flex-1 px-2 text-center text-xs font-medium text-white/90 tabular-nums drop-shadow-sm"
    >{text}</span
  >
  <button
    type="button"
    class="tap flex h-7 w-7 shrink-0 items-center justify-center rounded-md border border-white/10 bg-[#1a202c]/90 text-zinc-300 shadow-sm transition-colors select-none hover:border-white/20 hover:bg-[#252d3d] hover:text-white active:bg-[#2d374a] disabled:opacity-40"
    aria-label={i18n.t.card.increment}
    disabled={incrementDisabled}
    onclick={(event) => step(event, 1)}><Plus size={14} aria-hidden="true" /></button
  >
</div>

{#if error}
  <p class="text-xs leading-4 text-rose-300" role="alert">
    {errorMessage(error)}
  </p>
{/if}
