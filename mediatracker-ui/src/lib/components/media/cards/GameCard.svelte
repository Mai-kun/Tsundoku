<script lang="ts">
    import type { GameMedia } from "$lib/types";
    import { i18n } from "$lib/i18n/index.svelte";
    import BaseCardContainer from "./BaseCardContainer.svelte";
    import CardProgressBar from "./CardProgressBar.svelte";
    import CardProgressControls from "./CardProgressControls.svelte";
    import CardTitleBlock from "./CardTitleBlock.svelte";
    import {
        createCardProgress,
        supportsProgressStepper,
    } from "./cardProgress.svelte";
    import type { MediaCardProps } from "./cardTypes";

    let {
        item,
        onOpen = () => {},
        onProgress,
        onProgressCommitted = () => {},
        onStatusChange,
        onDelete,
    }: MediaCardProps & { item: GameMedia } = $props();

    const progress = createCardProgress({
        getItem: () => item,
        getOnProgress: () => onProgress,
        getOnProgressCommitted: () => onProgressCommitted,
    });
    const showStepper = $derived(supportsProgressStepper(item));

    /** Games list every platform shipped on; only the user's pick is meaningful. */
    const platform = $derived(
        item.userPlatform?.trim() || item.platform?.trim() || null,
    );
</script>

<BaseCardContainer
    {item}
    {onOpen}
    {onStatusChange}
    {onProgressCommitted}
    {onDelete}
>
    <CardTitleBlock
        title={item.title}
        subtitle={platform ?? i18n.t.types.game}
    />

    <CardProgressBar label={i18n.t.card.hours(progress.value)} ratio={null} />

    {#if showStepper}
        <CardProgressControls {progress} />
    {/if}
</BaseCardContainer>