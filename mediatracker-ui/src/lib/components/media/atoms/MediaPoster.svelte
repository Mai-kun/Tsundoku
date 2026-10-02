<script lang="ts">
    import type { Snippet } from "svelte";
    import ImageIcon from "lucide-svelte/icons/image";

    interface Props {
        src: string | null;
        alt: string;
        /** Status + score cluster, rendered inside the poster's top-left corner. */
        badges?: Snippet;
        /** Destructive/secondary actions, rendered top-right and revealed on hover. */
        actions?: Snippet;
    }

    let { src, alt, badges, actions }: Props = $props();
</script>

<div class="aspect-[3/4] overflow-hidden rounded-lg bg-canvas">
    {#if src}
        <img
            {src}
            {alt}
            class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
            loading="lazy"
            decoding="async"
        />
    {:else}
        <div
            class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-muted"
        >
            <ImageIcon size={38} stroke-width={1.25} aria-hidden="true" />
        </div>
    {/if}

    <div
        class="absolute inset-x-0 top-0 z-10 flex items-start justify-between gap-2 p-2.5"
    >
        <div class="relative flex items-center">
            {@render badges?.()}
        </div>
        {#if actions}
            <div class="flex items-center gap-1.5">
                {@render actions()}
            </div>
        {/if}
    </div>
</div>