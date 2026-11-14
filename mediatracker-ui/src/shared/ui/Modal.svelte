<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    isOpen: boolean;
    onClose: () => void;
    labelledBy?: string;
    /** `md` — обычная модалка. `lg` — широкая панель (превью деталей). `xl` — расширенная модалка (настройки и т.д.). `search` — модалка поиска на 80% экрана. `jobs` — модалка фоновых процессов на ~90% экрана. */
    size?: "md" | "lg" | "xl" | "search" | "jobs";
    closable?: boolean;
    children: Snippet;
  }

  let { isOpen, onClose, labelledBy, size = "md", closable = true, children }: Props = $props();

  let dialogElement = $state<HTMLDialogElement | null>(null);
  let closingProgrammatically = false;
  let closeTimer: ReturnType<typeof setTimeout> | null = null;

  /** Matches the 150ms close animation; closing the dialog early would skip it. */
  const CLOSE_ANIMATION_MS = 160;

  /**
   * A press that starts inside the panel (selecting text) and ends on the backdrop is a drag, not
   * a dismissal — so the overlay only counts as clicked when BOTH mousedown and mouseup landed on
   * it (`target === dialogElement`, i.e. the backdrop area, never the panel's contents).
   */
  let pressedOnBackdrop = false;

  $effect(() => {
    const dialog = dialogElement;
    if (!dialog) return;

    if (isOpen && !dialog.open) {
      // A flip back to open during the close animation cancels it in place.
      if (closeTimer !== null) {
        clearTimeout(closeTimer);
        closeTimer = null;
      }
      closingProgrammatically = false;
      delete dialog.dataset.closing;
      pressedOnBackdrop = false;
      dialog.showModal();
    } else if (!isOpen && dialog.open) {
      closingProgrammatically = true;
      pressedOnBackdrop = false;
      // data-closing swaps the CSS to the exit keyframes; the native close waits them out.
      dialog.dataset.closing = "";
      closeTimer = setTimeout(() => {
        closeTimer = null;
        delete dialog.dataset.closing;
        dialog.close();
        closingProgrammatically = false;
      }, CLOSE_ANIMATION_MS);
    }
  });

  function handleCancel(event: Event) {
    event.preventDefault();
    if (closable) onClose();
  }

  function handleNativeClose() {
    if (closingProgrammatically) return;
    if (closable) onClose();
  }

  function handleMouseDown(event: MouseEvent) {
    if (!closable) return;
    pressedOnBackdrop = event.target === dialogElement;
  }

  function handleMouseUp(event: MouseEvent) {
    if (!closable) return;
    const startedOnBackdrop = pressedOnBackdrop;
    pressedOnBackdrop = false;
    if (startedOnBackdrop && event.target === dialogElement) onClose();
  }
</script>

<dialog
  bind:this={dialogElement}
  aria-labelledby={labelledBy}
  class="z-40 m-auto w-full {size === 'jobs'
    ? 'h-[88vh] max-h-[88vh] w-[92vw] max-w-[1600px]'
    : size === 'search'
      ? 'h-[85vh] max-h-[85vh] w-[95vw] max-w-[95vw] sm:h-[80vh] sm:max-h-[80vh] sm:w-[80vw] sm:max-w-[80vw]'
      : size === 'xl'
        ? 'h-[86vh] max-h-[90vh] w-[90vw] max-w-7xl'
        : size === 'lg'
          ? 'max-w-5xl'
          : 'max-w-2xl'} text-ink overflow-visible border-0 bg-transparent p-4 backdrop:bg-[#090b10]/80"
  style="contain: layout style;"
  onclose={handleNativeClose}
  oncancel={handleCancel}
  onmousedown={handleMouseDown}
  onmouseup={handleMouseUp}
>
  <!-- Fully opaque panel: only the ::backdrop carries the dim/blur, never the dialog
       surface itself, otherwise page content bleeds through the text. -->
  <div
    class="modal-panel overflow-hidden rounded-xl border border-white/[0.08] bg-[#151a26] shadow-2xl shadow-black/60 {size ===
      'xl' ||
    size === 'search' ||
    size === 'jobs'
      ? 'flex h-full min-h-0 flex-col'
      : ''}"
  >
    <div
      class={size === "xl" || size === "search" || size === "jobs"
        ? "flex h-full min-h-0 flex-col"
        : ""}
    >
      {@render children()}
    </div>
  </div>
</dialog>

<style>
  /* Entry: the backdrop fades (150–160ms) while the panel scales in from 0.96 with a
     decelerating ease. Opacity/transform only, never layout properties. */
  dialog[open]::backdrop {
    animation: modal-backdrop-in 160ms ease-out;
  }

  dialog[open] .modal-panel {
    animation: modal-panel-in 180ms cubic-bezier(0.16, 1, 0.3, 1);
  }

  /* Exit: data-closing is set while the dialog is still open, so the keyframes run out
     before the JS timer calls dialog.close(). forwards keeps the final faded frame. */
  dialog:global([data-closing])::backdrop {
    animation: modal-backdrop-out 150ms ease-in forwards;
  }

  dialog:global([data-closing]) .modal-panel {
    animation: modal-panel-out 150ms ease-in forwards;
  }

  @keyframes modal-backdrop-in {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes modal-backdrop-out {
    from {
      opacity: 1;
    }
    to {
      opacity: 0;
    }
  }

  @keyframes modal-panel-in {
    from {
      opacity: 0;
      transform: scale(0.96);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes modal-panel-out {
    from {
      opacity: 1;
      transform: scale(1);
    }
    to {
      opacity: 0;
      transform: scale(0.96);
    }
  }
</style>
