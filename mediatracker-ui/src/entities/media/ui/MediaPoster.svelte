<script lang="ts">
    import type { Snippet } from "svelte";
    import { Image as ImageIcon, LoaderCircle } from "$shared/ui/Icons.svelte";
    import { i18n } from "$shared/i18n/index.svelte";

    interface Props {
        src: string | null;
        alt: string;
        /** Status + score cluster, rendered inside the poster's top-left corner. */
        badges?: Snippet;
        /** Destructive/secondary actions, rendered top-right and revealed on hover. */
        actions?: Snippet;
        /** Background enrichment is still filling this item in. The card stays clickable. */
        syncing?: boolean;
    }

    let { src, alt, badges, actions, syncing = false }: Props = $props();
</script>

<div class="relative aspect-[3/4] overflow-hidden rounded-lg bg-canvas">
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

    {#if syncing}
        <div
            class="absolute inset-0 z-[5] flex flex-col items-center justify-center gap-2 bg-black/55 backdrop-blur-[1px]"
        >
            <LoaderCircle
                size={22}
                class="animate-spin text-white/90"
                aria-hidden="true"
            />
            <span
                class="rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold tracking-wide text-white/90"
            >
                {i18n.t.activity.syncing}
            </span>
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