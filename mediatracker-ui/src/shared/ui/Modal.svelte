<script lang="ts">
    import type { Snippet } from "svelte";

    interface Props {
        isOpen: boolean;
        onClose: () => void;
        labelledBy?: string;
        /** `md` — обычная модалка. `lg` — широкая панель (превью деталей). */
        size?: "md" | "lg";
        children: Snippet;
    }

    let { isOpen, onClose, labelledBy, size = "md", children }: Props = $props();

    let dialogElement = $state<HTMLDialogElement | null>(null);
    let closingProgrammatically = false;

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
            dialog.showModal();
        } else if (!isOpen && dialog.open) {
            closingProgrammatically = true;
            dialog.close();
            closingProgrammatically = false;
        }
    });

    function handleCancel(event: Event) {
        event.preventDefault();
        onClose();
    }

    function handleNativeClose() {
        if (closingProgrammatically) return;
        onClose();
    }

    function handleMouseDown(event: MouseEvent) {
        pressedOnBackdrop = event.target === dialogElement;
    }

    function handleMouseUp(event: MouseEvent) {
        const startedOnBackdrop = pressedOnBackdrop;
        pressedOnBackdrop = false;
        if (startedOnBackdrop && event.target === dialogElement) onClose();
    }
</script>

<dialog
    bind:this={dialogElement}
    aria-labelledby={labelledBy}
    class="z-40 m-auto w-full {size === 'lg'
        ? 'max-w-5xl'
        : 'max-w-2xl'} overflow-visible border-0 bg-transparent p-4 text-ink backdrop:bg-black/70 backdrop:backdrop-blur-sm"
    onclose={handleNativeClose}
    oncancel={handleCancel}
    onmousedown={handleMouseDown}
    onmouseup={handleMouseUp}
>
    <!-- Fully opaque panel: only the ::backdrop carries the dim/blur, never the dialog
       surface itself, otherwise page content bleeds through the text. -->
    <div
        class="overflow-hidden rounded-xl border border-white/[0.08] bg-[#151a26] shadow-2xl shadow-black/60"
    >
        <div>
            {@render children()}
        </div>
    </div>
</dialog>
