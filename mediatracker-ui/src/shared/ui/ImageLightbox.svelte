<script lang="ts">
    import { X } from "$shared/ui/Icons.svelte";

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
        class="fixed inset-0 z-[100000] flex items-center justify-center p-4 sm:p-8 backdrop-blur-md bg-black/85 text-white"
    >
        <button
            type="button"
            onclick={close}
            class="absolute top-4 right-4 z-50 shrink-0 rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20 focus:outline-none focus:ring-2 focus:ring-white/40 cursor-pointer"
            aria-label="Закрыть"
        >
            <X size={24} />
        </button>

        <div class="relative flex items-center justify-center max-w-full max-h-[90dvh]">
            <img
                src={url}
                alt=""
                class="max-w-full max-h-[90dvh] rounded-lg shadow-2xl border border-white/20 zoom-in object-contain scale-100"
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
