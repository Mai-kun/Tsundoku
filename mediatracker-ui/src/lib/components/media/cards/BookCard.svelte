<script lang="ts">
    import type { BookMedia } from "$lib/types";
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
    }: MediaCardProps & { item: BookMedia } = $props();

    const progress = createCardProgress({
        getItem: () => item,
        getOnProgress: () => onProgress,
        getOnProgressCommitted: () => onProgressCommitted,
    });
    const showStepper = $derived(supportsProgressStepper(item));
    const ratio = $derived(
        item.totalPages > 0 ? progress.value / item.totalPages : null,
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
        subtitle={item.author || i18n.t.types.book}
    />

    <CardProgressBar
        label={i18n.t.card.pages(progress.value, item.totalPages)}
        {ratio}
        reserveSpace={showStepper}
    />

    {#if showStepper}
        <CardProgressControls {progress} />
    {/if}
</BaseCardContainer>