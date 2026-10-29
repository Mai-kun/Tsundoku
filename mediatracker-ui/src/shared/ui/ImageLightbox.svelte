<script lang="ts">
  import { X } from "$shared/ui/Icons";

  interface Props {
    url?: string | null;
    onclose?: () => void;
  }

  let { url = null, onclose }: Props = $props();

  let box = $state<HTMLDivElement | null>(null);

  $effect(() => {
    if (!url || !box) return;
    box.focus();
  });

  function close() {
    onclose?.();
  }

  function handleBackdropClick(event: MouseEvent) {
    if (event.target === box) close();
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === "Escape") close();
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if url}
  <div
    bind:this={box}
    tabindex="-1"
    role="dialog"
    aria-modal="true"
    aria-label="Увеличенное изображение"
    onclick={handleBackdropClick}
    onkeydown={handleKeydown}
    class="fixed inset-0 z-[100000] flex items-center justify-center bg-black/85 p-4 text-white backdrop-blur-md sm:p-8"
  >
    <button
      type="button"
      onclick={close}
      class="absolute top-4 right-4 z-50 shrink-0 cursor-pointer rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20 focus:ring-2 focus:ring-white/40 focus:outline-none"
      aria-label="Закрыть"
    >
      <X size={24} />
    </button>

    <div class="relative flex max-h-[90dvh] max-w-full items-center justify-center">
      <img
        src={url}
        alt=""
        class="zoom-in max-h-[90dvh] max-w-full scale-100 rounded-lg border border-white/20 object-contain shadow-2xl"
      />
    </div>
  </div>
{/if}

<style>
  .zoom-in {
    animation: zoomIn 220ms cubic-bezier(0.16, 1, 0.3, 1) both;
  }

  @keyframes zoomIn {
    from {
      transform: scale(0.92);
      opacity: 0;
    }

    to {
      transform: scale(1);
      opacity: 1;
    }
  }
</style>
