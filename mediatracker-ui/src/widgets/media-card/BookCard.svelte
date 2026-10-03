<script lang="ts">
    import type { BookMedia } from "$shared/types";
    import { i18n } from "$shared/i18n/index.svelte";
    import BaseCard from "./BaseCard.svelte";
    import CardProgressBar from "./CardProgressBar.svelte";
    import CardProgressControls from "./CardProgressControls.svelte";
    import CardTitleBlock from "./CardTitleBlock.svelte";
    import { createCardProgress } from "$features/update-progress/progressController.svelte";
    import { supportsProgressStepper } from "$entities/media/model/progressRules";
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

<BaseCard
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
</BaseCard>